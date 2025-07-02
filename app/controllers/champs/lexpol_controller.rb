# frozen_string_literal: true

module Champs
  class LexpolController < Champs::ChampController
    def upsert
      use_test_user = @champ.dossier&.revision&.draft?

      apilexpol = APILexpol.new(current_user.email, @champ.dossier&.procedure&.service&.siret, use_test_user)
      service = LexpolService.new(champ: @champ, dossier: @champ.dossier, apilexpol: apilexpol)

      force_create = params[:force_create].present?
      service.upsert_dossier(force_create: force_create)
      flash[:notice] = "Dossier Lexpol #{@champ.value.blank? ? 'créé' : 'mis à jour'} avec succès"
    rescue => e
      flash[:alert] = "Impossible de #{@champ.value.blank? ? "créer" : "mettre à jour"} le dossier Lexpol. #{e.message}"
    ensure
      redirect_back fallback_location: root_path
    end
  end
end
