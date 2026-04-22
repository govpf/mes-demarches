# frozen_string_literal: true

# pf: bascule instructeur entre l'affichage grille (nouveau) et empilé (ancien).
# Préférence stockée dans un cookie permanent — pas de migration DB.
module Instructeurs
  class DossierLayoutController < InstructeurController
    def update
      mode = params[:mode].to_s.to_sym
      if InstructeurChampDisplayHelper::LAYOUT_MODES.include?(mode)
        cookies.permanent[InstructeurChampDisplayHelper::LAYOUT_COOKIE] = mode.to_s
      end
      redirect_back fallback_location: root_url
    end
  end
end
