# frozen_string_literal: true

# pf: lien de vérification émis sur un document (cf. VerificationLinkToken)
module VerificationLinkConcern
  extend ActiveSupport::Concern

  include DateEncodingConcern

  def verification_link_token
    VerificationLinkToken.generate(*verification_link_resource)
  end

  # :token (jeton signé), :legacy (ancien format : date de création encodée) ou nil
  def verification_link_match(value)
    if VerificationLinkToken.token?(value)
      :token if VerificationLinkToken.valid?(value, *verification_link_resource)
    elsif VerificationLinkToken.legacy_allowed?(verification_link_first_emitted_at) && match_encoded_date?(:created_at, value.to_s)
      :legacy
    end
  end
end
