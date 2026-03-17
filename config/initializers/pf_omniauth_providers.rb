# frozen_string_literal: true

# pf: Configuration des providers OmniAuth spécifiques Polynésie française.
# Remplace l'accès à Rails.application.secrets supprimé dans Rails 7.2.
# Pattern identique à config/initializers/france_connect.rb.

protocol = Rails.env.production? ? 'https' : 'http'

PF_OMNIAUTH_PROVIDERS = {
  'sipf' => {
    identifier: ENV['SIPF_CLIENT_ID'],
    secret: ENV['SIPF_CLIENT_SECRET'],
    redirect_uri: "#{protocol}://#{ENV['APP_HOST']}/auth/sipf/callback",
    authorization_endpoint: "#{ENV.fetch('SIPF_CLIENT_BASE_URL', '')}/protocol/openid-connect/auth",
    token_endpoint: "#{ENV.fetch('SIPF_CLIENT_BASE_URL', '')}/protocol/openid-connect/token",
    userinfo_endpoint: "#{ENV.fetch('SIPF_CLIENT_BASE_URL', '')}/protocol/openid-connect/userinfo",
    logout_endpoint: "#{ENV.fetch('SIPF_CLIENT_BASE_URL', '')}/protocol/openid-connect/logout"
  },
  'tatou' => {
    identifier: ENV['TATOU_CLIENT_ID'],
    secret: ENV['TATOU_CLIENT_SECRET'],
    redirect_uri: "#{protocol}://#{ENV['APP_HOST']}/auth/tatou/callback",
    authorization_endpoint: "#{ENV.fetch('TATOU_BASE_URL', '')}/protocol/openid-connect/auth",
    token_endpoint: "#{ENV.fetch('TATOU_BASE_URL', '')}/protocol/openid-connect/token",
    userinfo_endpoint: "#{ENV.fetch('TATOU_BASE_URL', '')}/protocol/openid-connect/userinfo",
    logout_endpoint: "#{ENV.fetch('TATOU_BASE_URL', '')}/protocol/openid-connect/logout"
  },
  'microsoft' => {
    identifier: ENV['MICROSOFT_CLIENT_ID'],
    secret: ENV['MICROSOFT_CLIENT_SECRET'],
    redirect_uri: "#{protocol}://#{ENV['APP_HOST']}/auth/microsoft/callback",
    authorization_endpoint: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    token_endpoint: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
    userinfo_endpoint: 'https://graph.microsoft.com/oidc/userinfo',
    logout_endpoint: 'https://login.microsoftonline.com/common/oauth2/v2.0/logout'
  },
  'google' => {
    identifier: Rails.env.test? ? 'plop' : ENV['GOOGLE_CLIENT_ID'],
    secret: ENV['GOOGLE_CLIENT_SECRET'],
    redirect_uri: "#{protocol}://#{ENV['APP_HOST']}/auth/google/callback",
    authorization_endpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
    token_endpoint: 'https://oauth2.googleapis.com/token',
    userinfo_endpoint: 'https://openidconnect.googleapis.com/v1/userinfo',
    logout_endpoint: nil
  },
  'yahoo' => {
    identifier: ENV['YAHOO_CLIENT_ID'],
    secret: ENV['YAHOO_CLIENT_SECRET'],
    redirect_uri: "https://#{ENV['APP_HOST']}/auth/yahoo/callback",
    authorization_endpoint: 'https://api.login.yahoo.com/oauth2/request_auth',
    token_endpoint: 'https://api.login.yahoo.com/oauth2/get_token',
    userinfo_endpoint: 'https://api.login.yahoo.com/openid/v1/userinfo',
    logout_endpoint: nil
  }
}.freeze
