# frozen_string_literal: true

class OmniAuthService
  def self.enabled?(provider)
    ENV["#{provider.upcase}_CLIENT_ID"].present?
  end

  PROVIDERS = ['google', 'microsoft', 'yahoo', 'sipf', 'tatou']

  # pf: sécurité (F3/F4) — providers à identité forte (Keycloak opérés par la PF) dont
  # l'email asserté est toujours digne de confiance.
  STRONG_IDENTITY_PROVIDERS = ['tatou', 'sipf'].freeze

  def self.providers
    PROVIDERS.filter(&method(:enabled?))
  end

  # pf: sécurité (F3/F4) — l'email asserté par le provider est-il digne de confiance,
  # au point d'autoriser une connexion/fusion sans mot de passe ?
  # - identités fortes (Tatou, sipf) : toujours
  # - google/yahoo : seulement si le claim email_verified est vrai
  # - microsoft : seulement si le claim tid (immuable, anti-nOAuth) est dans l'allowlist
  #   MICROSOFT_ALLOWED_TENANTS ; fail-safe : allowlist vide => jamais de confiance
  def self.trusted_email_assertion?(provider:, email_verified: nil, tid: nil)
    if STRONG_IDENTITY_PROVIDERS.include?(provider)
      true
    elsif provider == 'microsoft'
      allowed_microsoft_tenants.include?(tid)
    else
      [true, 'true'].include?(email_verified)
    end
  end

  def self.allowed_microsoft_tenants
    ENV.fetch('MICROSOFT_ALLOWED_TENANTS', '').split(',').map(&:strip).compact_blank
  end

  def self.authorization_uri(provider)
    if provider.blank?
      raise "provider should not be nil"
    end
    client = OmniAuthClient.new(PF_OMNIAUTH_PROVIDERS[provider])
    scope = provider == 'yahoo' ? [:'sdpp-w'] : [:profile, :email]

    client.authorization_uri(
      scope: scope,
      state: SecureRandom.hex(16),
      nonce: SecureRandom.hex(16)
    )
  end

  def self.find_or_retrieve_user_informations(provider, code)
    fetched_fci = retrieve_user_informations(provider, code)
    FranceConnectInformation.find_by(france_connect_particulier_id: fetched_fci[:france_connect_particulier_id]) || fetched_fci
  end

  private

  def self.retrieve_user_informations(provider, code)
    if provider.blank?
      raise "provider should not be nil"
    end
    client = OmniAuthClient.new(PF_OMNIAUTH_PROVIDERS[provider], code)

    user_info = client.access_token!(client_auth_method: :secret)
      .userinfo!
      .raw_attributes

    FranceConnectInformation.new(
      gender: user_info[:gender],
      given_name: user_info[:given_name],
      family_name: user_info[:family_name],
      email_france_connect: user_info[:email],
      birthdate: user_info[:birthdate],
      birthplace: user_info[:birthplace],
      france_connect_particulier_id: user_info[:sub]
    )
  end
end
