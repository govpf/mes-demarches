# frozen_string_literal: true

class APIEntrepriseService
  # pf: ces jobs interrogent exclusivement entreprise.api.gouv.fr — ils n'ont
  # aucun sens sur un établissement issu du référentiel ISPF.
  # APIEntreprise::EtablissementJob en est volontairement absent : il appelle
  # update_etablissement_from_degraded_mode, qui dispatche entre les deux sources.
  FRENCH_ONLY_JOBS = [
    APIEntreprise::EntrepriseJob, APIEntreprise::ExtraitKbisJob, APIEntreprise::TvaJob,
    APIEntreprise::AssociationJob, APIEntreprise::ExercicesJob,
    APIEntreprise::EffectifsJob, APIEntreprise::EffectifsAnnuelsJob,
    APIEntreprise::AttestationSocialeJob, APIEntreprise::BilansBdfJob,
    APIEntreprise::AttestationFiscaleJob,
  ].freeze

  class << self
    # pf: un numéro Tahiti partiel (6 à 8 car.) peut correspondre à plusieurs
    # établissements. On les liste pour que l'usager choisisse.
    def list_etablissements(siret_prefix, procedure_id = nil)
      identifiant = IdentifiantEntreprise.parse(siret_prefix)
      return nil unless identifiant.tahiti_partiel?

      begin
        APIEntreprise::PfEtablissementAdapter.new(identifiant.valeur, procedure_id).to_all_etablissements
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
      identifiant = IdentifiantEntreprise.parse(siret)

      etablissement_params = if identifiant.tahiti_complet?
        APIEntreprise::PfEtablissementAdapter.new(identifiant.valeur, procedure_id).to_params
      elsif identifiant.siret?
        APIEntreprise::EtablissementAdapter.new(identifiant.valeur, procedure_id).to_params
      else
        # pf: numéro Tahiti partiel → passer par list_etablissements ;
        # numéro invalide → rien à résoudre.
        return nil
      end

      return nil if etablissement_params.blank?

      if identifiant.siret?
        entreprise_params = APIEntreprise::EntrepriseAdapter.new(identifiant.valeur, procedure_id).to_params
        etablissement_params.merge!(entreprise_params) if entreprise_params.any?
      end

      etablissement = dossier_or_champ.build_etablissement(etablissement_params)
      etablissement.save!

      if dossier_or_champ.is_a?(Champ)
        dossier_or_champ.update!(value_json: APIGeoService.parse_etablissement_address(etablissement))
      end
      # perform_later_fetch_jobs s'auto-garde depuis la phase 2 (nature du numéro
      # + présence du jeton) — pas de condition à dupliquer ici.
      perform_later_fetch_jobs(etablissement, procedure_id, user_id)
      # pf: la cascade explicite des formules est déclenchée par
      # Etablissement#update_champ_value_json! (couvre les cas Champ et Dossier).
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
      identifiant = IdentifiantEntreprise.parse(etablissement.siret)

      etablissement_params = if identifiant.tahiti?
        # pf: en mode dégradé, un numéro partiel ne peut pas être auto-complété
        # (plusieurs candidats possibles). On ne valide que si l'adapter a rendu
        # un numéro complet à 9 caractères.
        params = APIEntreprise::PfEtablissementAdapter.new(identifiant.valeur, procedure_id).to_params
        return nil unless params.present? && IdentifiantEntreprise.parse(params[:siret]).tahiti_complet?

        params
      elsif identifiant.siret?
        APIEntreprise::EtablissementAdapter.new(identifiant.valeur, procedure_id).to_params
      else
        return nil
      end
      return nil if etablissement_params.empty?

      etablissement.update!(etablissement_params)
      etablissement.update_champ_value_json!

      etablissement
    end

    def perform_later_fetch_jobs(etablissement, procedure_id, user_id, wait: nil)
      # pf: sans jeton (procédure ou ENV), ces jobs lèvent tous TokenError et
      # finissent morts dans Sidekiq. Un jeton spécifique sur la procédure reste honoré.
      return if Procedure.find_by(id: procedure_id)&.api_entreprise_token&.jwt_token.blank?

      identifiant = IdentifiantEntreprise.parse(etablissement.siret)

      jobs = []
      # EtablissementJob sait router les deux référentiels : il vaut pour un
      # numéro Tahiti comme pour un SIRET.
      jobs << APIEntreprise::EtablissementJob if etablissement.as_degraded_mode?
      # pf: les autres jobs sont strictement français — poser API_ENTREPRISE_KEY
      # ne doit pas les déclencher sur les établissements issus de l'ISPF.
      jobs.concat(FRENCH_ONLY_JOBS) if identifiant.siret?

      jobs.each do |job|
        if job == APIEntreprise::AttestationFiscaleJob
          job.set(wait:).perform_later(etablissement.id, procedure_id, user_id)
        else
          job.set(wait:).perform_later(etablissement.id, procedure_id)
        end
      end
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

    def service_unavailable_error?(error, target:, identifiant: nil)
      return false if !error.try(:network_error?)

      if target == :insee
        # pf: deux fournisseurs — sonder celui qui a réellement été interrogé.
        # Sans identifiant, on retombe sur l'ISPF (référentiel dominant en PF).
        return true if identifiant&.siret? ? !fr_api_insee_up? : !api_insee_up?
      end
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
