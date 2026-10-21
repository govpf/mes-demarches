# frozen_string_literal: true

# pf: Job pour rafraîchir les données d'un champ Lexpol individuel
# Stratégie de fallback (Lexpol : un dossier « En préparation » n'est visible que de son rédacteur) :
#   1. L'auteur du dossier Lexpol (compte enregistré à la création, à défaut le dernier
#      agent ayant créé ou mis à jour le champ)
#   2. Les instructeurs qui suivent le dossier
#   3. Le compte de service du numéro Tahiti du service (si configuré)
# Pour un dossier de test, le dossier Lexpol a été créé avec le compte de service
# s'il est configuré : on commence alors par lui, les agents servant de repli.
class RefreshLexpolChampJob < ApplicationJob
  queue_as :default

  # pf: Ne pas retenter automatiquement car :
  # - Les erreurs LexpolAccessDenied sont gérées par le fallback instructeurs
  # - Les vraies erreurs techniques sont loggées dans Sentry
  discard_on ActiveRecord::RecordNotFound

  # pf: Lexpol indisponible (timeout, 429, 5xx) : on retente plus tard,
  # sinon le champ reste périmé jusqu'au cron du lendemain
  retry_on APILexpol::LexpolUnavailable, wait: :polynomially_longer, attempts: 5 do |job, error|
    Sentry.capture_exception(error, extra: { champ_id: job.arguments.first })
  end

  def perform(champ_id)
    champ = Champs::LexpolChamp.find(champ_id)

    # Ignorer les champs sans NOR
    return if champ.value.blank?

    # pf: Ignorer les champs qui ont déjà un lien arrêté (immuable)
    return if champ.lexpol_arrete_lien.present?

    dossier = champ.dossier

    success = if test_dossier_with_service_account?(dossier)
      try_refresh_with_service_account(champ, dossier) || try_refresh_with_agents(champ, dossier)
    else
      # pf: Tous les agents ont échoué : dernier fallback sur compte de service
      try_refresh_with_agents(champ, dossier) || try_refresh_with_service_account(champ, dossier)
    end

    Rails.logger.info("Lexpol data refreshed for champ #{champ.id}, NOR: #{champ.value}") if success

  rescue APILexpol::LexpolUnavailable
    raise # pf: géré par retry_on
  rescue StandardError => e
    # pf: Erreur technique inattendue : log mais ne pas bloquer les autres rafraîchissements
    Rails.logger.error("Unexpected error refreshing Lexpol champ #{champ.id}: #{e.message}")
    Sentry.capture_exception(e, extra: {
      champ_id: champ.id,
      dossier_id: dossier&.id,
      nor: champ.value,
    })
  end

  private

  # pf: numéro Tahiti du SERVICE de la démarche (celui de LEXPOL_SERVICE_EMAILS),
  # et non celui de l'entreprise du demandeur (dossier.etablissement)
  def service_numero_tahiti(dossier)
    dossier.procedure.service&.siret
  end

  def test_dossier_with_service_account?(dossier)
    numero_tahiti = service_numero_tahiti(dossier)
    dossier.revision&.draft? && numero_tahiti.present? && APILexpol.service_emails[numero_tahiti].present?
  end

  # pf: un 401 à l'authentification vaut pour tous les dossiers (compte non habilité) :
  # on le mémorise pour ne pas retenter l'authentification à chaque champ du lot
  AUTH_DENIED_TTL = 10.minutes

  # pf: comptes personnels à essayer, dans l'ordre, sans doublon
  def agent_emails(champ, dossier)
    auteur = champ.lexpol_auteur_email.presence || champ.updated_by.presence
    suiveurs = dossier.followers_instructeurs.map(&:email)

    [auteur, *suiveurs].compact.uniq
  end

  # pf: Essaie de rafraîchir avec les comptes personnels des agents
  # Retourne true si succès, false si tous ont échoué
  def try_refresh_with_agents(champ, dossier)
    emails = agent_emails(champ, dossier).reject { |email| auth_denied?(email) }

    if emails.empty?
      Rails.logger.warn("Lexpol: No agent account to try for dossier #{dossier.id}, will try service account")
      return false
    end

    numero_tahiti = service_numero_tahiti(dossier)
    emails.each_with_index do |email, index|
      apilexpol = APILexpol.new(email, numero_tahiti, false) # use_test_user: false
      LexpolService.new(champ: champ, dossier: dossier, apilexpol: apilexpol).refresh_lexpol_data!

      Rails.logger.info("Lexpol: Success with fallback agent #{email} (#{index + 1}/#{emails.size})") if index > 0
      return true
    rescue APILexpol::LexpolAccessDenied => e
      # pf: 401 = compte non habilité dans Lexpol, 403 = dossier non visible pour ce compte
      remember_auth_denied(email) if e.http_code == 401
      Rails.logger.warn("Lexpol: Access denied (HTTP #{e.http_code}) for #{email} (#{index + 1}/#{emails.size}), trying next")
    end

    Rails.logger.error("Lexpol: All agents failed for dossier #{dossier.id}")
    Sentry.capture_message("Lexpol: All instructeurs lack access", extra: {
      dossier_id: dossier.id,
      instructeur_emails: emails,
      nor: champ.value,
    })
    false
  end

  def auth_denied?(email)
    Rails.cache.exist?(auth_denied_cache_key(email))
  end

  def remember_auth_denied(email)
    Rails.cache.write(auth_denied_cache_key(email), true, expires_in: AUTH_DENIED_TTL)
  end

  def auth_denied_cache_key(email)
    "lexpol_auth_denied_#{email}"
  end

  # pf: Dernier fallback : essayer avec le compte de service
  # (configuré via LEXPOL_SERVICE_EMAILS pour l'organisation)
  def try_refresh_with_service_account(champ, dossier)
    numero_tahiti = service_numero_tahiti(dossier)

    # Vérifier si un compte de service est configuré
    if numero_tahiti.blank? || APILexpol.service_emails[numero_tahiti].blank?
      Rails.logger.error("Lexpol: No service account configured for SIRET #{numero_tahiti}, giving up")
      return false
    end

    begin
      # pf: Utiliser l'email de n'importe quel instructeur comme base,
      # mais avec use_test_user: true pour forcer le compte de service
      email = dossier.followers_instructeurs.first&.email || dossier.user_email_for(:notification)
      apilexpol = APILexpol.new(email, numero_tahiti, true) # use_test_user: true
      service = LexpolService.new(champ: champ, dossier: dossier, apilexpol: apilexpol)

      service.refresh_lexpol_data!

      Rails.logger.info("Lexpol: Success with service account for dossier #{dossier.id}")
      true

    rescue APILexpol::LexpolAccessDenied => e
      # pf: Même le compte de service échoue : situation critique
      Rails.logger.error("Lexpol: Even service account failed for dossier #{dossier.id}: #{e.message}")
      Sentry.capture_exception(e, extra: {
        dossier_id: dossier.id,
        nor: champ.value,
        service_email: e.email_used,
        siret: numero_tahiti,
      })
      false
    end
  end
end
