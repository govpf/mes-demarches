# frozen_string_literal: true

# pf: En Polynésie française, ProConnect est remplacé par Microsoft @administration.gov.pf
# Ce concern permet de restreindre l'accès à certaines procédures sensibles
# en obligeant les instructeurs/administrateurs à s'authentifier via leur compte professionnel.
module ProConnectSessionConcern
  extend ActiveSupport::Concern

  SESSION_INFO_COOKIE_NAME = :pro_connect_session_info

  included do
    def logged_in_with_pro_connect?
      # pf: En PF, l'authentification professionnelle = Microsoft @administration.gov.pf
      # Contrairement à l'upstream qui utilise un cookie chiffré, nous utilisons
      # l'attribut loged_in_with_france_connect qui est déjà géré par le système PF

      # upstream (France métropolitaine) :
      # current_user.present? && cookies.encrypted[SESSION_INFO_COOKIE_NAME].present? && JSON.parse(cookies.encrypted[SESSION_INFO_COOKIE_NAME])['user_id'] == current_user.id

      # pf (Polynésie française) :
      current_user.present? && current_user.loged_in_with_france_connect == 'microsoft'
    end

    def set_pro_connect_session_info_cookie(user_id)
      # pf: Pas de cookie en PF, on utilise loged_in_with_france_connect
      # L'attribut est automatiquement mis à jour lors de la connexion Microsoft

      # upstream (France métropolitaine) :
      # cookies.encrypted[SESSION_INFO_COOKIE_NAME] = { value: { user_id: }.to_json, secure: Rails.env.production?, httponly: true }

      # pf (Polynésie française) :
      # Méthode vide pour compatibilité avec le code upstream
    end

    def delete_pro_connect_session_info_cookie
      # pf: Pas de cookie en PF
      # L'attribut loged_in_with_france_connect est automatiquement écrasé
      # lors d'une nouvelle connexion (Tatou, mot de passe, etc.)

      # upstream (France métropolitaine) :
      # cookies.delete SESSION_INFO_COOKIE_NAME

      # pf (Polynésie française) :
      # Méthode vide pour compatibilité avec le code upstream
    end
  end
end
