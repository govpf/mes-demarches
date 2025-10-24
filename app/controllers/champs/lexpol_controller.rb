# frozen_string_literal: true

module Champs
  class LexpolController < Champs::ChampController
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
      apilexpol = APILexpol.new(current_user.email, @champ.dossier&.procedure&.service&.siret, should_use_test_user?)
      service = LexpolService.new(champ: @champ, dossier: @champ.dossier, apilexpol: apilexpol, user: current_user)

      @variables = service.build_variables

      # Informations sur les dossiers liés pour le groupement côté frontend
      linked_service = LinkedDossierFieldsService.new(@champ.dossier, current_user)
      linked_info = linked_service.linked_dossiers_info

      render json: { variables: @variables.sort.to_h, linked_dossiers: linked_info }
    rescue => e
      Sentry.capture_exception(e)
      render json: { error: "Impossible de générer la prévisualisation: #{e.message}" }, status: :unprocessable_entity
    end

    private

    def should_use_test_user?
      # Utilise un compte de service pour :
      # - Les super admins (tests en production)
      # - Les révisions brouillon (développement)
      super_admin_signed_in? || @champ.dossier&.revision&.draft?
    end
  end
end
