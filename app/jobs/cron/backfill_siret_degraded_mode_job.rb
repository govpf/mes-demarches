# frozen_string_literal: true

# pf: Job qui tente de récupérer les données des établissements en mode dégradé
# Si la récupération échoue (numéro invalide, introuvable, etc.),
# demande automatiquement une correction à l'usager
class Cron::BackfillSiretDegradedModeJob < Cron::CronJob
  self.schedule_expression = "every 2 hour"

  def perform(*args)
    fix_etablissements_with_auto_correction
  end

  private

  def fix_etablissements_with_auto_correction
    # Établissements avec dossier direct
    Etablissement.joins(:dossier)
      .where(adresse: nil)
      .includes(dossier: [:groupe_instructeur, :followers_instructeurs, :pending_corrections])
      .find_each do |etablissement|

      handle_etablissement(etablissement, etablissement.dossier, source: :dossier)
    end

    # Établissements via champs SIRET
    Etablissement.joins(:champ)
      .where(adresse: nil)
      .includes(champ: { dossier: [:groupe_instructeur, :followers_instructeurs, :pending_corrections] })
      .find_each do |etablissement|

      handle_etablissement(etablissement, etablissement.champ.dossier, source: :champ, champ: etablissement.champ)
    end
  end

  def handle_etablissement(etablissement, dossier, source:, champ: nil)
    procedure_id = dossier.procedure.id

    begin
      # Tentative de récupération des données
      result = APIEntrepriseService.update_etablissement_from_degraded_mode(etablissement, procedure_id)

      if result
        puts "✅ Backfill réussi: #{etablissement.siret} (dossier ##{dossier.id})"
      else
        # Échec → demander correction immédiatement
        request_correction(etablissement, dossier, source, champ)
      end

    rescue => e
      puts "❌ Exception pour établissement #{etablissement.id}: #{e.message}"
      Sentry.capture_exception(e, extra: { etablissement_id: etablissement.id, dossier_id: dossier.id })
    end
  end

  def request_correction(etablissement, dossier, source, champ)
    # Protections : pas de doublon et dossier doit pouvoir recevoir une correction
    return if dossier.pending_corrections.any?
    return unless dossier.may_flag_as_pending_correction?

    # Trouver un instructeur
    instructeur = dossier.followers_instructeurs.first ||
                  dossier.groupe_instructeur&.instructeurs&.first
    return unless instructeur

    # Message adapté selon la source (champ vs établissement)
    message = correction_message(etablissement.siret, dossier, source, champ)

    # Créer la correction
    commentaire = Commentaire.create!(
      dossier: dossier,
      instructeur: instructeur,
      body: message
    )

    dossier.flag_as_pending_correction!(commentaire, :incorrect)

    puts "📧 Correction demandée: dossier ##{dossier.id} (#{source})"
  rescue => e
    puts "❌ Impossible de demander correction pour dossier ##{dossier.id}: #{e.message}"
    Sentry.capture_exception(e, extra: { dossier_id: dossier.id })
  end

  def correction_message(siret, dossier, source, champ)
    error_reason = detect_error_reason(siret)

    if source == :champ
      # pf: Message pour un champ SIRET/Tahiti
      champ_name = champ&.libelle || "Numéro TAHITI"
      link = "#{APPLICATION_BASE_URL}/dossiers/#{dossier.id}/modifier"

      <<~MSG
        Bonjour,

        #{error_explanation(siret, error_reason)}

        Merci de corriger le champ « #{champ_name} » de votre dossier :
        #{link}

        Cordialement,
        L'équipe #{APPLICATION_NAME}
      MSG
    else
      # pf: Message pour l'identité entreprise du dossier
      link = "#{APPLICATION_BASE_URL}/dossiers/#{dossier.id}/etablissement"

      <<~MSG
        Bonjour,

        #{error_explanation(siret, error_reason)}

        Merci de modifier l'identité de votre entreprise :
        #{link}

        Cordialement,
        L'équipe #{APPLICATION_NAME}
      MSG
    end
  end

  def detect_error_reason(siret)
    cleaned = siret.to_s.gsub(/[[:space:]-]/, "")

    case cleaned.length
    when 0..5
      :too_short
    when 6..8
      :ambiguous
    when 10..13
      :invalid_length
    when 9, 14
      :not_found
    else
      :invalid_length
    end
  end

  def error_explanation(siret, reason)
    case reason
    when :not_found
      "Le numéro TAHITI « #{siret} » n'a pas été trouvé dans le registre des entreprises de Polynésie française."
    when :ambiguous
      "Le numéro TAHITI « #{siret} » est incomplet. Plusieurs établissements correspondent à ce numéro.\n" \
      "Un numéro TAHITI complet contient 9 chiffres (6 chiffres entreprise + 3 chiffres établissement)."
    when :too_short, :invalid_length
      "Le numéro TAHITI « #{siret} » ne respecte pas le format attendu.\n" \
      "Un numéro TAHITI valide contient 9 chiffres (6 chiffres entreprise + 3 chiffres établissement)."
    else
      "Le numéro TAHITI « #{siret} » n'a pas pu être vérifié automatiquement."
    end
  end
end
