# frozen_string_literal: true

module Champs
  class LexpolController < Champs::ChampController
    def upsert
      apilexpol = APILexpol.new(current_user.email, @champ.dossier&.procedure&.service&.siret, should_use_test_user?)
      service = LexpolService.new(champ: @champ, dossier: @champ.dossier, apilexpol: apilexpol)

      force_create = params[:force_create].present?
      service.upsert_dossier(force_create: force_create)
      flash[:notice] = "Dossier Lexpol #{@champ.value.blank? ? 'créé' : 'mis à jour'} avec succès"
    rescue JSON::ParserError
      flash[:alert] = "Erreur de communication avec Lexpol"
    rescue => e
      if e.message.include?('401')
        flash[:alert] = "Accès non autorisé - Vérifiez votre enregistrement sur Lexpol"
      else
        flash[:alert] = "Impossible de #{@champ.value.blank? ? "créer" : "mettre à jour"} le dossier Lexpol. #{e.message}"
      end
    ensure
      redirect_back fallback_location: root_path
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
