# frozen_string_literal: true

module Champs
  class LexpolController < Champs::ChampController
    skip_before_action :set_champ, only: [:preview_variables]

    def upsert
      apilexpol = APILexpol.new(current_user.email, @champ.dossier&.procedure&.service&.siret, should_use_test_user?)
      service = LexpolService.new(champ: @champ, dossier: @champ.dossier, apilexpol: apilexpol, user: current_user)

      force_create = params[:force_create].present?
      service.upsert_dossier(force_create: force_create)
      flash[:notice] = "Dossier Lexpol #{@champ.value.blank? ? 'créé' : 'mis à jour'} avec succès"
    rescue JSON::ParserError => e
      Sentry.capture_message("Invalid Json received from Lexpol : #{e.message}")
      flash[:alert] = "Erreur de communication avec Lexpol"

    rescue => e
      if e.message.include?('401')
        flash[:alert] = "Accès non autorisé - Vérifiez votre enregistrement sur Lexpol"
      else
        Sentry.capture_exception(e)
        flash[:alert] = "Impossible de #{@champ.value.blank? ? "créer" : "mettre à jour"} le dossier Lexpol. #{e.message}"
      end
    ensure
      redirect_back fallback_location: root_path
    end

    def preview_variables
      # pf: Récupérer le dossier et le type de champ sans passer par set_champ
      dossier = policy_scope(Dossier).includes(:champs, revision: [:types_de_champ]).find(params[:dossier_id])
      type_de_champ = dossier.find_type_de_champ_by_stable_id(params[:stable_id])

      return render json: { error: 'Type de champ introuvable' }, status: :not_found unless type_de_champ

      temp_champ = build_temp_champ(dossier, type_de_champ)
      apilexpol = APILexpol.new(current_user.email, dossier.procedure&.service&.siret, should_use_test_user_for_dossier?(dossier))
      service = LexpolService.new(champ: temp_champ, dossier: dossier, apilexpol: apilexpol, user: current_user)

      variables = service.build_variables
      grouped = group_variables(variables, dossier)

      render json: { grouped_variables: grouped }
    rescue => e
      Sentry.capture_exception(e)
      render json: { error: 'Impossible de générer la prévisualisation' }, status: :unprocessable_entity
    end

    private

    def build_temp_champ(dossier, type_de_champ)
      # Créer un champ temporaire pour le service (sans le sauvegarder)
      # Note: instance_variable_set est utilisé car type_de_champ est une méthode calculée
      # sans setter. Acceptable ici car le champ est temporaire et non persisté.
      temp_champ = Champs::LexpolChamp.new(
        dossier: dossier,
        stable_id: type_de_champ.stable_id,
        private: type_de_champ.private?
      )
      temp_champ.instance_variable_set(:@type_de_champ, type_de_champ)
      temp_champ
    end

    def group_variables(variables, dossier)
      procedure = dossier.procedure
      column_labels = (procedure.dossier_columns_for_export + procedure.usager_columns_for_export).map(&:label)

      linked_service = LinkedDossierFieldsService.new(dossier, current_user)
      # Ne garder que les suffixes des dossiers accessibles
      linked_suffixes = linked_service.linked_dossiers_info
        .filter { |info| info[:accessible] }
        .map { |info| info[:suffixe] }

      metadonnees = variables.filter { |k, _v| column_labels.include?(k) }
      dossiers_lies = variables.filter { |k, _v| linked_suffixes.any? { |suffix| k.end_with?(" (#{suffix})") } }
      champs_formulaire = variables.except(*metadonnees.keys, *dossiers_lies.keys)

      {
        metadonnees: metadonnees.sort.to_h,
        champs_formulaire: champs_formulaire.sort.to_h,
        dossiers_lies: dossiers_lies.sort.to_h
      }
    end

    def should_use_test_user?
      # Utilise un compte de service pour :
      # - Les super admins (tests en production)
      # - Les révisions brouillon (développement)
      super_admin_signed_in? || @champ.dossier&.revision&.draft?
    end

    def should_use_test_user_for_dossier?(dossier)
      super_admin_signed_in? || dossier.revision&.draft?
    end
  end
end
