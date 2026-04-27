# frozen_string_literal: true

class Champs::SiretChamp < Champ
  include Dry::Monads[:result]
  validate :validate_etablissement, if: :validate_champ_value?
  # pf: accept and strip hyphens too, Tahiti numbers can be formatted as "G33972-001"
  normalizes :external_id, with: -> siret { siret.gsub(/[[:space:]-]/, "") }

  def uses_external_data?
    true
  end

  # TODO: remove after T20251029backfillChampSiretExternalStateTask
  def external_id
    idle? && etablissement_id.present? ? value : super
  end

  def after_reset_external_data(opts = {})
    super(etablissement_id: nil, prefilled: false, value: nil)
  end

  def update_external_data!(data:)
    # pf: when auto-completed from a 6-char Tahiti prefix to 9-char, keep the full number as the stored value
    if data[:external_id].present?
      update(etablissement: data[:etablissement], external_id: data[:external_id], value: data[:external_id])
    else
      update(etablissement: data[:etablissement], value: external_id)
    end
  end

  def ready_for_external_call?
    # pf: accept SIRET (14 chars) and Tahiti numbers (6/9 chars) + partial Tahiti (7-8 chars) to trigger the candidates list
    return false if external_id.blank?

    case external_id.length
    when 14
      Siret.new(siret: external_id).valid?
    when 6..9
      true
    else
      false
    end
  end

  def fetch_external_data
    siret = external_id.to_s

    # pf: partial Tahiti number (6-8 chars): list candidates rather than a single lookup
    return fetch_tahiti_candidates(siret) if siret.length.between?(6, 8)

    etablissement = APIEntrepriseService.create_etablissement(self, siret, dossier.user&.id)
    if etablissement.blank?
      Failure(retryable: false, reason: StandardError.new('NotFound'), code: 404)
    else
      Success(etablissement:)
    end
  rescue APIEntrepriseToken::TokenError => error
    Failure(retryable: false, reason: error, code: 401)
  rescue APIEntreprise::API::Error => error
    if APIEntrepriseService.service_unavailable_error?(error, target: :insee)
      update!(
        etablissement: APIEntrepriseService.create_etablissement_as_degraded_mode(self, siret, dossier.user&.id)
      )
      Failure(retryable: true, reason: error, code: 503)
    else
      Sentry.capture_exception(error, extra: { dossier_id:, siret: external_id })
      Failure(retryable: false, reason: error, code: 500)
    end
  end

  def search_terms
    etablissement.present? ? etablissement.search_terms : [value]
  end

  def mandatory_blank?
    mandatory? && value.blank?
  end

  # pf: list of candidate etablissements when external_state is multiple_found
  def etablissement_candidates
    return [] unless multiple_found?
    (data || {}).fetch('multiple_found', []) || []
  end

  def save_additional_job_exception(exception, code)
    exceptions = fetch_external_data_exceptions || []
    exceptions << ExternalDataException.new(reason: exception.inspect, code:)
    update_columns(fetch_external_data_exceptions: exceptions)
  end

  private

  # pf: query ISPF for a partial Tahiti number and dispatch on result count
  def fetch_tahiti_candidates(siret_prefix)
    candidates = APIEntrepriseService.list_etablissements(siret_prefix, procedure.id)

    return Failure(retryable: false, reason: StandardError.new('NotFound'), code: 404) if candidates.blank?

    if candidates.size == 1
      # pf: single match: auto-complete to the full 9-char Tahiti number and create the etablissement
      candidate = candidates.first
      full_siret = "#{siret_prefix}#{format('%03d', candidate[:num_entreprise])}"
      etablissement = APIEntrepriseService.create_etablissement_from_pf_candidate(self, full_siret, candidate)
      Success(etablissement:, external_id: full_siret)
    else
      Success(multiple_found: candidates)
    end
  end

  # We want to validate if SIRET really exists
  # It's valid when an etablissement have been created after fetch_external_data
  # When API Entreprise is down, user won't be stuck because
  # create_etablissement_as_degraded_mode creates an etablissement in degraded mode
  def validate_etablissement
    return if external_id.blank?
    return if etablissement.present?
    return if pending?

    if multiple_found?
      # pf: user must pick one etablissement from the list before the dossier is valid
      errors.add(:external_id, :multiple_found)
      return
    end

    # pf: custom SiretValidator accepts SIRET (14) and Tahiti (6/9)
    validator = SiretValidator.new(attributes: { external_id: true })
    validator.validate_each(self, :external_id, external_id)

    errors.add(:external_id, :not_found) if errors.empty?
  end
end
