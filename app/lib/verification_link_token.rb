# frozen_string_literal: true

# pf: jeton des liens de vérification émis sur les documents (QR code d'attestation,
# pièce justificative). Le lien vaut autorisation de lecture pour qui détient le
# document : le jeton doit donc être impossible à deviner.
#
# Clés dédiées et versionnées : VERIFICATION_LINK_KEYS="2:<clé>,1:<clé>".
# La première signe, toutes vérifient. Retirer une version invalide les liens émis avec.
# Sans cette variable, on dérive une clé (version 0) de secret_key_base.
#
# Ancien format (date de création encodée) : accepté pour les seuls liens qui ont pu être émis
# avant VERIFICATION_LINK_LEGACY_UNTIL (date de mise en production des jetons signés), c'est-à-dire
# un dossier traité avant cette date pour le QR code, déposé avant cette date pour une pièce justificative.
# Sans cette variable, l'ancien format reste accepté partout.
class VerificationLinkToken
  ENV_KEY = 'VERIFICATION_LINK_KEYS'
  LEGACY_UNTIL_ENV_KEY = 'VERIFICATION_LINK_LEGACY_UNTIL'
  DERIVED_VERSION = '0'
  DIGEST_BYTES = 16
  MIN_KEY_LENGTH = 32
  FORMAT = /\Ak(?<version>\d+)_(?<digest>[A-Za-z0-9_-]{22})\z/

  class InvalidConfiguration < StandardError; end

  class << self
    def generate(*resource)
      version, key = keys.first
      "k#{version}_#{digest(key, resource)}"
    end

    def valid?(token, *resource)
      match = FORMAT.match(token.to_s)
      key = match && keys[match[:version]]
      return false if key.nil?

      ActiveSupport::SecurityUtils.secure_compare(match[:digest], digest(key, resource))
    end

    # un jeton à l'ancien format (date encodée en hexadécimal) ne commence jamais par k
    def token?(value)
      value.to_s.start_with?('k')
    end

    def keys
      @keys ||= configured_keys.merge(DERIVED_VERSION => derived_key).freeze
    end

    def legacy_allowed?(first_emitted_at)
      legacy_until.nil? || (first_emitted_at.present? && first_emitted_at < legacy_until)
    end

    def legacy_until
      return @legacy_until if defined?(@legacy_until)

      value = ENV[LEGACY_UNTIL_ENV_KEY].presence
      @legacy_until = value && (Time.zone.parse(value) || raise(ArgumentError))
    rescue ArgumentError
      raise InvalidConfiguration, "#{LEGACY_UNTIL_ENV_KEY} : date invalide (#{value.inspect}), attendu par exemple 2026-11-20T08:00:00-10:00"
    end

    def reset!
      @keys = nil
      remove_instance_variable(:@legacy_until) if defined?(@legacy_until)
    end

    private

    def digest(key, resource)
      hmac = OpenSSL::HMAC.digest('SHA256', key, resource.map(&:to_s).join(':'))
      [hmac.byteslice(0, DIGEST_BYTES)].pack('m0').tr('+/', '-_').delete('=')
    end

    def configured_keys
      ENV.fetch(ENV_KEY, '').split(',').map(&:strip).compact_blank.each_with_object({}) do |entry, keys|
        version, key = entry.split(':', 2)
        if !version.match?(/\A[1-9]\d*\z/) || key.to_s.length < MIN_KEY_LENGTH || keys.key?(version)
          raise InvalidConfiguration, "#{ENV_KEY} : entrée invalide pour la version #{version.inspect} (attendu <entier>:<clé de #{MIN_KEY_LENGTH} caractères ou plus>, versions uniques)"
        end

        keys[version] = key
      end
    end

    def derived_key
      Rails.application.key_generator.generate_key('verification_link_token', 32)
    end
  end
end
