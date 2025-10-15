# frozen_string_literal: true

# pf: Configuration omniauth uniquement pour RDV Service Public
# Nos providers custom (Google, Microsoft, Tatou) utilisent OmniAuthService/OpenIDConnect directement
# et ne doivent pas être interceptés par le middleware omniauth

Rails.application.config.middleware.use OmniAuth::Builder do
  # Configuration pour désactiver l'interception automatique des routes /auth/:provider
  # Cela permet à nos routes custom d'être traitées normalement
  configure do |config|
    config.path_prefix = '/auth/rdv_service_public'
  end
  
  provider :rdv_service_public, ENV["RDV_SERVICE_PUBLIC_OAUTH_APP_ID"], ENV["RDV_SERVICE_PUBLIC_OAUTH_APP_SECRET"],
           scope: "write", base_url: ENV["RDV_SERVICE_PUBLIC_URL"]

  # on_failure do |env|
  #   Sentry.capture_exception(env["omniauth.error"])

  #   # redirect to the root path
  #   redirect_to root_path
  # end
end
