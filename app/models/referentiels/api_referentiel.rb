# frozen_string_literal: true

class Referentiels::APIReferentiel < Referentiel
  # An encrypted JSON object is used to store authentication data securely and flexibly.
  # This allows us to store various authentication methods in a single field.
  # Examples of authentication_data structure:
  #
  #   Basic Auth : { "username": "...", "password": "..." }
  #   OAuth2 : { "client_id": "...", "client_secret": "...", "token_url": "..." }
  #   Custom header : { "header": "X-API-Key", "value": "..." }
  #   JWT : { "header": "Authorization", "value": "Bearer ...", "jwt_options": {...} }
  encrypts :authentication_data

  enum :mode, {
    exact_match: 'exact_match',
    autocomplete: 'autocomplete',
  }

  validates :mode, inclusion: { in: modes.values }
  validate :url_allowed?
  validates :test_data, presence: true
  validates :url, presence: true

  store_accessor :autocomplete_configuration, :datasource, :json_template
  before_save :name_as_uuid
  before_save :resets_tiptap_template

  def self.stub_url
    ENV.fetch('ALLOWED_API_DOMAINS_FROM_FRONTEND')
      .split(',')
      .last
  end

  def self.csv_available?
    false
  end

  def resets_tiptap_template
    if datasource_changed? && !datasource_was.nil?
      self.json_template = {}
    end
  end

  def tiptap_template=(value)
    self.json_template = JSON.parse(value)
  end

  def tiptap_template
    json_template&.to_json
  end

  def last_response_body
    (last_response || {}).fetch("body") { {} }
  end

  def needs_autocomplete_configuration_step?
    autocomplete?
  end

  def last_response_status
    (last_response || {}).fetch("status") { 500 }
  end

  def ready?
    configured? && last_response_status == 200
  end

  def needs_autocomplete_configuration?
    autocomplete?
  end

  def configured?
    case type
    when "Referentiels::APIReferentiel"
      [mode, url, test_data].all?(&:present?)
    when "Referentiels::CsvReferentiel"
      false
    else
      false
    end
  end

  def authentication_data_header
    authentication_data&.fetch('header', '')
  end

  def authentication_header_token
    authentication_data&.fetch('value', '')
  end

  def authentication_by_header_token?
    [
      authentication_method == 'header_token',
      authentication_data_header.present?,
      authentication_header_token.present?,
    ].all?
  end

  # pf: reprise manuelle du correctif upstream c6c3275169. Sa version s'appuie sur l'URL TipTap,
  # que nous n'avons pas encore : on applique les mêmes règles à notre URL à paramètre {id}.
  #   - https obligatoire
  #   - domaine autorisé par égalité ou sous-domaine, plus par simple inclusion de chaîne
  # Le correctif upstream 8029aadd80 (paramètre dans le nom de domaine) est sans objet ici :
  # une URL dont {id} touche le nom de domaine est déjà refusée comme invalide.
  def url_allowed?
    return if url.blank?

    uri = Addressable::URI.parse(url)

    errors.add(:url, :https_required) if uri.scheme != 'https'

    unless uri.tld == "gouv.fr" && uri.domain != "beta.gouv.fr"
      if uri.host.blank? || allowed_hosts.none? { uri.host == _1 || uri.host.end_with?(".#{_1}") }
        errors.add(:url, :not_allowed, contact_email: CONTACT_EMAIL)
      end
    end
  rescue Addressable::URI::InvalidURIError, URI::InvalidURIError, PublicSuffix::DomainInvalid
    errors.add(:url, :invalid_format)
  end

  private

  def allowed_hosts
    ENV.fetch('ALLOWED_API_DOMAINS_FROM_FRONTEND', '').split(',').filter_map do |entry|
      Addressable::URI.parse(entry.strip).host
    rescue Addressable::URI::InvalidURIError
      nil
    end
  end

  def name_as_uuid # should be uniq, using the url was an idea but not unique
    self.name = SecureRandom.uuid
  end
end
