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

  # pf: sécurité (F2) — state et nonce sont fournis par le contrôleur qui les stocke en
  # session, pour pouvoir les valider au callback (anti-CSRF OAuth). Ils ne doivent plus
  # être générés ici (sinon non vérifiables au retour).
  def self.authorization_uri(provider, state:, nonce:)
    if provider.blank?
      raise "provider should not be nil"
    end
    client = OmniAuthClient.new(PF_OMNIAUTH_PROVIDERS[provider])
    scope = provider == 'yahoo' ? [:'sdpp-w'] : [:profile, :email]

    client.authorization_uri(
      scope: scope,
      state:,
      nonce:
    )
  end

  def self.find_or_retrieve_user_informations(provider, code)
    fetched_fci = retrieve_user_informations(provider, code)
    fci = FranceConnectInformation.find_by(france_connect_particulier_id: fetched_fci.france_connect_particulier_id) || fetched_fci
    # pf: sécurité (F3/F4) — la confiance est transitoire (claims de l'auth courante),
    # à reporter sur la FCI persistée éventuellement retrouvée.
    fci.trusted_email_assertion = fetched_fci.trusted_email_assertion
    fci
  end

  private

  def self.retrieve_user_informations(provider, code)
    if provider.blank?
      raise "provider should not be nil"
    end
    client = OmniAuthClient.new(PF_OMNIAUTH_PROVIDERS[provider], code)

    access_token = client.access_token!(client_auth_method: :secret)
    user_info = access_token.userinfo!.raw_attributes
    id_token_claims = decode_id_token_claims(access_token)

    fci = FranceConnectInformation.new(
      gender: user_info[:gender],
      given_name: user_info[:given_name],
      family_name: user_info[:family_name],
      email_france_connect: user_info[:email],
      birthdate: user_info[:birthdate],
      birthplace: user_info[:birthplace],
      france_connect_particulier_id: user_info[:sub]
    )

    # pf: sécurité (F3/F4) — tid et email_verified viennent de l'id_token (le userinfo
    # Microsoft ne porte pas tid). email_verified peut aussi être dans le userinfo.
    email_verified = id_token_claims['email_verified']
    email_verified = user_info[:email_verified] if email_verified.nil?
    fci.trusted_email_assertion = trusted_email_assertion?(
      provider:,
      email_verified:,
      tid: id_token_claims['tid']
    )
    fci
  end

  # pf: sécurité — décode les claims de l'id_token. En flux authorization-code, l'id_token
  # vient du token endpoint en back-channel TLS direct => authentique sans vérif de
  # signature (les providers PF n'ont pas de jwks configuré ; vérif JWKS = suivi).
  def self.decode_id_token_claims(access_token)
    raw = access_token.id_token
    return {} if raw.blank?

    JSON::JWT.decode(raw, :skip_verification).to_h
  rescue => e
    Rails.logger.error("OmniAuth id_token decode failed: #{e.message}")
    {}
  end
end
