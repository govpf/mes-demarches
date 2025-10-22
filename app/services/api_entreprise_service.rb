# frozen_string_literal: true

class APIEntrepriseService
  class << self
    # PF: Specific method for handling ambiguous TAHITI numbers (< 9 chars)
    # In French Polynesia, a 6-char TAHITI number can match multiple establishments
    # This method lists all possible establishments for user selection
    def list_etablissements(siret_prefix, procedure_id = nil)
      return nil unless siret_prefix.present? && siret_prefix.length < 9

      begin
        adapter = APIEntreprise::PfEtablissementAdapter.new(siret_prefix, procedure_id)
        adapter.to_all_etablissements
      rescue APIEntreprise::API::Error::ResourceNotFound
        nil
      end
    end

    # create etablissement with EtablissementAdapter
    # enqueue api_entreprise jobs to retrieve
    # all informations we can get about a SIRET.
    #
    # Returns the etablissement if created, nil if the SIRET is unknown
    #
    # Raises a APIEntreprise::API::Error::RequestFailed exception on transient errors
    # (timeout, 5XX HTTP error code, etc.)
    def create_etablissement(dossier_or_champ, siret, user_id = nil)
      procedure_id = dossier_or_champ.procedure.id

      # PF: Handle 9-char TAHITI numbers (6 chars company + 3 chars establishment)
      etablissement_params = if siret.length == 9
        APIEntreprise::PfEtablissementAdapter.new(siret, procedure_id).to_params
      elsif siret.length > 9
        APIEntreprise::EtablissementAdapter.new(siret, procedure_id).to_params
      else
        # PF: SIRET < 9 chars is ambiguous, use list_etablissements instead
        return nil
      end

      return nil if etablissement_params.blank?

      if siret.length > 9
        entreprise_params = APIEntreprise::EntrepriseAdapter.new(siret, procedure_id).to_params
        etablissement_params.merge!(entreprise_params) if entreprise_params.any?
      end

      etablissement = dossier_or_champ.build_etablissement(etablissement_params)
      etablissement.save!

      if dossier_or_champ.is_a?(Champ)
        dossier_or_champ.update!(value_json: APIGeoService.parse_etablissement_address(etablissement))
      end
      if siret.length > 9
        perform_later_fetch_jobs(etablissement, procedure_id, user_id)
      end
      etablissement.update_champ_value_json!
      etablissement
    end

    def create_etablissement_as_degraded_mode(dossier_or_champ, siret, user_id = nil)
      etablissement = dossier_or_champ.build_etablissement(siret: siret)
      etablissement.save!

      procedure_id = dossier_or_champ.procedure.id

      perform_later_fetch_jobs(etablissement, procedure_id, user_id, wait: 30.minutes)

      etablissement
    end

    def update_etablissement_from_degraded_mode(etablissement, procedure_id)
      siret = etablissement.siret
      # PF: Support 9-char TAHITI numbers in degraded mode
      etablissement_params = if siret.length == 9
        APIEntreprise::PfEtablissementAdapter.new(siret, procedure_id).to_params
      elsif siret.length > 9
        APIEntreprise::EtablissementAdapter.new(siret, procedure_id).to_params
      else
        # PF: SIRET < 9 chars should not be in degraded mode (ambiguous)
        return nil
      end
      return nil if etablissement_params.empty?

      etablissement.update!(etablissement_params)
      etablissement.update_champ_value_json!

      etablissement
    end

    def perform_later_fetch_jobs(etablissement, procedure_id, user_id, wait: nil)
      jobs = [
        APIEntreprise::EntrepriseJob, APIEntreprise::ExtraitKbisJob, APIEntreprise::TvaJob,
        APIEntreprise::AssociationJob, APIEntreprise::ExercicesJob,
        APIEntreprise::EffectifsJob, APIEntreprise::EffectifsAnnuelsJob, APIEntreprise::AttestationSocialeJob,
        APIEntreprise::BilansBdfJob
      ]
      if etablissement.as_degraded_mode?
        jobs << APIEntreprise::EtablissementJob
      end
      jobs.each do |job|
        job.set(wait:).perform_later(etablissement.id, procedure_id)
      end

      APIEntreprise::AttestationFiscaleJob.set(wait:).perform_later(etablissement.id, procedure_id, user_id)
    end

    # See: https://entreprise.api.gouv.fr/developpeurs#surveillance-etat-fournisseurs
    def api_insee_up?
      APIEntreprise::PfAPI.api_up?
    end

    def fr_api_insee_up?
      api_up?("https://entreprise.api.gouv.fr/ping/insee/sirene")
    end

    def api_djepva_up?
      api_up?("https://entreprise.api.gouv.fr/ping/djepva/api-association")
    end

    def service_unavailable_error?(error, target:)
      return false if !error.try(:network_error?)
      return true if target == :insee && !APIEntrepriseService.api_insee_up?
      return true if target == :djepva && !APIEntrepriseService.api_djepva_up?
      error.is_a?(APIEntreprise::API::Error::ServiceUnavailable)
    end

    private

    def api_up?(url)
      response = Typhoeus.get(url, timeout: 1)
      if response.success?
        JSON.parse(response.body).fetch('status') == 'ok'
      else
        false
      end
    rescue => e
      Sentry.capture_exception(e)
      false
    end
  end
end
