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
      # pf: la cascade explicite des formules est déclenchée par
      # Etablissement#update_champ_value_json! (couvre les deux cas Champ et
      # Dossier-level — formules qui lisent entreprise.raison_commerciale).
      etablissement.update_champ_value_json!
      etablissement
    end

    # pf: fast path when the partial Tahiti number returned a single candidate via list_etablissements;
    def create_etablissement_from_pf_candidate(dossier_or_champ, full_siret, candidate)
      params = candidate.except(:num_entreprise).merge(siret: full_siret)
      params[:siege_social] = true if candidate[:num_entreprise].to_i == 1

      etablissement = dossier_or_champ.build_etablissement(params)
      etablissement.save!

      if dossier_or_champ.is_a?(Champ)
        dossier_or_champ.update!(value_json: APIGeoService.parse_etablissement_address(etablissement))
      end
      # pf: cascade des formules déclenchée par update_champ_value_json!
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
      # pf: Support TAHITI numbers (6-9 chars) in degraded mode
      # For 6-char numbers, validate only if there's a single establishment (95% of cases)
      etablissement_params = if siret.length >= 6 && siret.length <= 9
        adapter = APIEntreprise::PfEtablissementAdapter.new(siret, procedure_id)
        params = adapter.to_params

        # If SIRET was not completed (still 6 chars), it means multiple establishments exist
        # In this case, we can't auto-validate in degraded mode
        if params.present? && params[:siret].present? && params[:siret].length == 9
          params
        else
          # Multiple establishments or error: can't auto-complete
          return nil
        end
      elsif siret.length > 9
        APIEntreprise::EtablissementAdapter.new(siret, procedure_id).to_params
      else
        # Invalid SIRET length
        return nil
      end
      return nil if etablissement_params.empty?

      etablissement.update!(etablissement_params)
      etablissement.update_champ_value_json!

      etablissement
    end

    def perform_later_fetch_jobs(etablissement, procedure_id, user_id, wait: nil)
      # pf: pas de jeton API Entreprise en Polynésie — sans jeton (procédure ou ENV),
      # ces jobs lèvent tous TokenError et finissent morts dans Sidekiq. On ne les
      # lance pas ; un jeton spécifique configuré sur la procédure reste honoré.
      return if Procedure.find_by(id: procedure_id)&.api_entreprise_token&.jwt_token.blank?

      jobs = [
        APIEntreprise::EntrepriseJob, APIEntreprise::ExtraitKbisJob, APIEntreprise::TvaJob,
        APIEntreprise::AssociationJob, APIEntreprise::ExercicesJob,
        APIEntreprise::EffectifsJob, APIEntreprise::EffectifsAnnuelsJob, APIEntreprise::AttestationSocialeJob,
        APIEntreprise::BilansBdfJob,
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
