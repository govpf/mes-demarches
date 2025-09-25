# frozen_string_literal: true

module SiretChampEtablissementFetchableConcern
  extend ActiveSupport::Concern

  # PF: Changed from :other_etablissements to :etablissements
  # Stores the list of possible establishments when a partial TAHITI number is ambiguous
  attr_reader :etablissement_fetch_error_key, :etablissements

  def fetch_etablissement!(siret, user)
    return clear_etablissement!(:empty) if siret.empty?
    return clear_etablissement!(:invalid_length) if invalid_because?(siret, :length) # i18n-tasks-use t('errors.messages.invalid_siret_length')
    return clear_etablissement!(:invalid_checksum) if invalid_because?(siret, :checksum) # i18n-tasks-use t('errors.messages.invalid_siret_checksum')

    # PF: Branch logic based on SIRET length
    # < 9 chars = ambiguous TAHITI number (PF specific)
    # >= 9 chars = complete SIRET/TAHITI number
    if siret.length < 9
      handle_ambiguous_siret(siret, user)
    else
      handle_complete_siret(siret, user)
    end
  rescue APIEntreprise::API::Error, APIEntrepriseToken::TokenError => error
    handle_api_error(error, siret, user)
  end

  private

  # PF: Handle partial TAHITI numbers that may match multiple establishments
  # This is specific to PF where users can enter 6-char company numbers
  # Upstream doesn't have this case
  def handle_ambiguous_siret(siret, user)
    etablissements = APIEntrepriseService.list_etablissements(siret, procedure.id)
    return clear_etablissement!(:not_found) if etablissements.blank? # i18n-tasks-use t('errors.messages.siret_not_found')

    if etablissements.size == 1
      # PF: Auto-select when only one establishment matches
      full_siret = "#{siret}#{format('%03d', etablissements[0][:num_entreprise])}"
      create_and_update_etablissement(full_siret, user)
    else
      # The @etablissements array will be used by the view
      @etablissements = etablissements
      true
    end
  end

  def handle_complete_siret(siret, user)
    create_and_update_etablissement(siret, user)
  end

  def create_and_update_etablissement(siret, user)
    etablissement = APIEntrepriseService.create_etablissement(self, siret, user&.id)
    return clear_etablissement!(:not_found) unless etablissement # i18n-tasks-use t('errors.messages.siret_not_found')

    update!(etablissement:)
  end

  def handle_api_error(error, siret, user)
    if APIEntrepriseService.service_unavailable_error?(error, target: :insee)
      update!(
        etablissement: APIEntrepriseService.create_etablissement_as_degraded_mode(self, siret, user.id)
      )
      @etablissement_fetch_error_key = :api_entreprise_down
      false
    else
      Sentry.capture_exception(error, extra: { dossier_id:, siret: })
      clear_etablissement!(:network_error) # i18n-tasks-use t('errors.messages.siret_network_error')
    end
  end

  def clear_etablissement!(error_key)
    @etablissement_fetch_error_key = error_key

    etablissement_to_destroy = etablissement
    update!(etablissement: nil)
    etablissement_to_destroy&.destroy

    false
  end

  def invalid_because?(siret, criteria)
    validatable_siret = Siret.new(siret: siret)
    return false if validatable_siret.valid?

    validatable_siret.errors.details[:siret].any? && validatable_siret.errors.details[:siret].first[:error] == criteria
  end
end
