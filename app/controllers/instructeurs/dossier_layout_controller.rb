# frozen_string_literal: true

# pf: bascule instructeur entre l'affichage grille et empilé + dismiss du bandeau
# - mode=grid|stacked : persiste la préférence en DB (instructeurs.dossier_layout_preference) — sert
#                       aussi au tracking agrégé (proportion d'instructeurs ayant choisi le nouvel affichage)
# - mode=dismissed    : pose un cookie éphémère de fermeture du bandeau (pas d'impact sur le layout, pas d'écriture DB)
module Instructeurs
  class DossierLayoutController < InstructeurController
    def update
      mode = params[:mode].to_s.to_sym

      if InstructeurChampDisplayHelper::LAYOUT_MODES.include?(mode)
        current_instructeur.update!(dossier_layout_preference: mode.to_s)
      elsif mode == :dismissed
        cookies[InstructeurChampDisplayHelper::DISMISSED_COOKIE] = {
          value: Time.current.iso8601,
          expires: InstructeurChampDisplayHelper::FEATURE_ROLLOUT_DATE + InstructeurChampDisplayHelper::BANNER_DURATION,
        }
      end

      respond_to do |format|
        format.html { redirect_back fallback_location: root_url }
        format.json { head :no_content }
      end
    end
  end
end
