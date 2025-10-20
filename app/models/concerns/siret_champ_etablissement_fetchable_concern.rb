# frozen_string_literal: true

module SiretChampEtablissementFetchableConcern
  extend ActiveSupport::Concern

  # pf: Stores the list of possible establishments when a partial TAHITI number is ambiguous
  # Also stores error keys for better error handling in PF context
  attr_reader :etablissement_fetch_error_key, :etablissements

  def fetch_etablissement!(siret, user)
    return clear_etablissement!(:empty) if siret.empty?

    cleaned_siret = siret.gsub(/[[:space:]-]/, "")

    # pf: Handle different validation approaches based on number length
    case cleaned_siret.length
    when 0..5
      # pf: Too short even for partial Tahiti numbers
      return clear_etablissement!(:invalid_length)
    when 6..8
      # pf: Partial Tahiti numbers - handle ambiguous cases
      handle_ambiguous_siret(cleaned_siret, user)
    when 9
      # pf: Complete Tahiti number (9 chars)
      handle_complete_siret(cleaned_siret, user)
    when 14
      handle_french_siret(cleaned_siret, user)
    else
      # Invalid length for both systems
      return clear_etablissement!(:invalid_length)
    end
  rescue APIEntreprise::API::Error, APIEntrepriseToken::TokenError => error
    handle_api_error(error, cleaned_siret, user)
  end

  private

  # pf: Handle partial TAHITI numbers that may match multiple establishments
  # This is specific to PF where users can enter 6-char company numbers
  def handle_ambiguous_siret(siret, user)
    etablissements = APIEntrepriseService.list_etablissements(siret, procedure.id)
    return clear_etablissement!(:not_found) if etablissements.blank? # i18n-tasks-use t('errors.messages.siret_not_found')

    if etablissements.size == 1
      # PF: Auto-select when only one establishment matches
      full_siret = "#{siret}#{format('%03d', etablissements[0][:num_entreprise])}"
      # Keep the etablissements list for auto-selection in the view
      @etablissements = etablissements
      create_and_update_etablissement(full_siret, user)
    else
      # The @etablissements array will be used by the view
      @etablissements = etablissements
      true
    end
  end

  # pf: Handle complete Tahiti numbers (9 chars)
  def handle_complete_siret(siret, user)
    create_and_update_etablissement(siret, user)
  end

  def handle_french_siret(siret, user)
    return clear_etablissement!(:invalid_checksum) if Siret.new(siret:).invalid?

    create_and_update_etablissement(siret, user)
  end

  def create_and_update_etablissement(siret, user)
    # Debug temporaire
    Rails.logger.info "[DEBUG] Trying to create etablissement for SIRET: #{siret} (length: #{siret.length})"

    etablissement = APIEntrepriseService.create_etablissement(self, siret, user&.id)

    Rails.logger.info "[DEBUG] Etablissement result: #{etablissement.inspect}"

    return clear_etablissement!(:not_found) unless etablissement

    update!(etablissement:)
  end

  def handle_api_error(error, siret, user)
    if APIEntrepriseService.service_unavailable_error?(error, target: :insee)
      update!(
        etablissement: APIEntrepriseService.create_etablissement_as_degraded_mode(self, siret, user.id)
      )
      false
    else
      Sentry.capture_exception(error, extra: { dossier_id:, siret: })
      clear_etablissement!(:api_error)
    end
  end

  # pf: Enhanced clear_etablissement! method that supports error keys for PF
  def clear_etablissement!(error_key = nil)
    @etablissement_fetch_error_key = error_key if error_key

    etablissement_to_destroy = etablissement
    update!(etablissement: nil)
    etablissement_to_destroy&.destroy

    false
  end
end
