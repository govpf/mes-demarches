# frozen_string_literal: true

# pf: une configuration mal formée doit empêcher le démarrage, pas casser les liens en silence
Rails.application.config.after_initialize do
  VerificationLinkToken.keys
  VerificationLinkToken.legacy_until
end
