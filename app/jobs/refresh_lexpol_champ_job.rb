# frozen_string_literal: true

# pf: Job pour rafraîchir les données d'un champ Lexpol individuel
# Stratégie de fallback :
#   1. Essai avec le premier instructeur du dossier
#   2. Si erreur d'accès, essai avec les autres instructeurs
#   3. Si tous échouent, essai avec le compte de service (si configuré)
class RefreshLexpolChampJob < ApplicationJob
  queue_as :default

  # pf: Ne pas retenter automatiquement car :
  # - Les erreurs LexpolAccessDenied sont gérées par le fallback instructeurs
  # - Les vraies erreurs techniques sont loggées dans Sentry
  discard_on ActiveRecord::RecordNotFound

  def perform(champ_id)
    champ = Champs::LexpolChamp.find(champ_id)

    # Ignorer les champs sans NOR
    return if champ.value.blank?

    # pf: Ignorer les champs qui ont déjà un lien arrêté (immuable)
    return if champ.lexpol_arrete_lien.present?

    dossier = champ.dossier

    # pf: Essayer de rafraîchir avec les instructeurs (avec fallback)
    success = try_refresh_with_instructeurs(champ, dossier)

    if success
      Rails.logger.info("Lexpol data refreshed for champ #{champ.id}, NOR: #{champ.value}")
    else
      # pf: Tous les instructeurs ont échoué : dernier fallback sur compte de service
      try_refresh_with_service_account(champ, dossier)
    end

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

  # pf: Essaie de rafraîchir avec les instructeurs du dossier
  # Retourne true si succès, false si tous les instructeurs ont échoué
  def try_refresh_with_instructeurs(champ, dossier)
    instructeurs = dossier.followers_instructeurs.to_a

    if instructeurs.empty?
      Rails.logger.warn("Lexpol: No instructeur found for dossier #{dossier.id}, will try service account")
      return false
    end

    # pf: Essayer avec chaque instructeur jusqu'à réussir
    instructeurs.each_with_index do |instructeur, index|
      begin
        numero_tahiti = dossier.etablissement&.siret
        apilexpol = APILexpol.new(instructeur.email, numero_tahiti, false) # use_test_user: false
        service = LexpolService.new(champ: champ, dossier: dossier, apilexpol: apilexpol)

        service.refresh_lexpol_data!

        # Succès !
        if index > 0
          Rails.logger.info("Lexpol: Success with fallback instructeur #{instructeur.email} (#{index + 1}/#{instructeurs.size})")
        end
        return true

      rescue APILexpol::LexpolAccessDenied
        # pf: Cet instructeur n'a pas accès : essayer le suivant
        Rails.logger.warn("Lexpol: Access denied for instructeur #{instructeur.email} (#{index + 1}/#{instructeurs.size}), trying next")

        # Si c'est le dernier instructeur, on continue vers le compte de service
        next if index < instructeurs.size - 1

        # Dernier instructeur échoué
        Rails.logger.error("Lexpol: All instructeurs failed for dossier #{dossier.id}")
        Sentry.capture_message("Lexpol: All instructeurs lack access", extra: {
          dossier_id: dossier.id,
          instructeur_emails: instructeurs.map(&:email),
          nor: champ.value,
        })
        return false
      end
    end

    false
  end

  # pf: Dernier fallback : essayer avec le compte de service
  # (configuré via LEXPOL_SERVICE_EMAILS pour l'organisation)
  def try_refresh_with_service_account(champ, dossier)
    numero_tahiti = dossier.etablissement&.siret

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
