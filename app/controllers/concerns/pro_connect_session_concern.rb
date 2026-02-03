# frozen_string_literal: true

# pf: En Polynésie française, ProConnect est remplacé par Microsoft @administration.gov.pf
# Ce concern permet de restreindre l'accès à certaines procédures sensibles
# en obligeant les instructeurs/administrateurs à s'authentifier via leur compte professionnel.
module ProConnectSessionConcern
  extend ActiveSupport::Concern

  SESSION_INFO_COOKIE_NAME = :pro_connect_session_info

  included do
    def logged_in_with_pro_connect?
      # pf: Gestion hybride pour supporter à la fois :
      # - upstream ProConnect (cookie chiffré)
      # - PF Microsoft @administration.gov.pf (loged_in_with_france_connect)
      return false if current_user.blank?

      # upstream : vérification via cookie ProConnect
      cookie_check = cookies.encrypted[SESSION_INFO_COOKIE_NAME].present? &&
                     JSON.parse(cookies.encrypted[SESSION_INFO_COOKIE_NAME])['user_id'] == current_user.id

      # pf : vérification via attribut Microsoft
      microsoft_check = current_user.loged_in_with_france_connect == 'microsoft'

      cookie_check || microsoft_check
    end

    def set_pro_connect_session_info_cookie(user_id)
      # pf: Gestion hybride - on set le cookie pour compatibilité upstream ProConnect
      cookies.encrypted[SESSION_INFO_COOKIE_NAME] = { value: { user_id: }.to_json, secure: Rails.env.production?, httponly: true }
    end

    def delete_pro_connect_session_info_cookie
      # pf: Gestion hybride - on delete le cookie pour compatibilité upstream ProConnect
      # Note : en PF, loged_in_with_france_connect est écrasé lors de la prochaine connexion
      cookies.delete SESSION_INFO_COOKIE_NAME
    end
  end
end
