# frozen_string_literal: true

require 'typhoeus'
require 'json'

class APILexpol
  # pf: Exception spécifique pour les erreurs d'accès (401/403)
  # Permet de distinguer les problèmes de permissions des autres erreurs techniques
  class LexpolAccessDenied < StandardError
    attr_reader :email_used, :http_code

    def initialize(email_used, http_code)
      @email_used = email_used
      @http_code = http_code
      super("Accès refusé à Lexpol pour #{email_used} (HTTP #{http_code})")
    end
  end
  # Syntaxe de LEXPOL_SERVICE_EMAILS :
  # Cette variable d'environnement doit contenir une liste de numéros Tahiti avec leurs emails associés.
  # Format attendu : "T123456(email1),D654321(email2),003970(email3)"
  # Exemple : "003970(admin@example.com),D123456(manager@example.com)"

  BASE_URL = ENV.fetch('LEXPOL_BASE_URL', 'https://devapilexpol.cloud.pf/api/v1/geda')
  TOKEN_EXPIRATION_TIME = 290 # less than 5 minutes
  MODEL_EXPIRATION_TIME = 900 # 15 min

  def initialize(email, numero_tahiti = nil, use_test_user = false)
    raise ArgumentError, "Email requis" if email.blank?

    @email_agent = determine_email_agent(email, numero_tahiti, use_test_user)
    @use_certificate = ENV.fetch('LEXPOL_CERTIFICATE_ENABLED', '').casecmp('enabled').zero?
  end

  def authenticate
    Rails.cache.fetch("lexpol_token_#{@email_agent}", expires_in: TOKEN_EXPIRATION_TIME) do
      request_authentication
    end
  end

  def get_models
    Rails.cache.fetch("lexpol_models_#{@email_agent}", expires_in: MODEL_EXPIRATION_TIME) do
      body = request(:get, "/modeles", 'Erreur lors de la récupération des modèles')
      body['modeles'].map { |model| [model['libelle'], model['modele']] }
    end
  end

  def create_dossier(modele_id, variables = {})
    request(:post, "/dossier", "l'envoi des variables à Lexpol", { modele: modele_id, variables: variables.presence })&.fetch('nor', nil)
  end

  def update_dossier(nor, variables)
    request(:put, "/dossier/#{nor}/modifier", "L'envoi des variables à Lexpol", { variables: variables })&.fetch('nor', nil)
  end

  def get_dossier_status(nor)
    request(:get, "/dossier/#{nor}/statut", 'La récupération du statut du dossier Lexpol')&.slice('statut', 'libelle')
  end

  def get_dossier_infos(nor)
    request(:get, "/dossier/#{nor}/infos", 'La récupération des informations du dossier Lexpol')
  end

  private

  LEXPOL_SERVICE_EMAILS = ENV.fetch('LEXPOL_SERVICE_EMAILS', '').scan(/([A-Z0-9][0-9]{5})\(([^)]+)\)/).to_h

  def determine_email_agent(email, numero_tahiti, use_test_user)
    # Si on ne demande pas de compte de test, utiliser l'email fourni
    return email unless use_test_user

    # Si pas de numéro Tahiti (SIRET), impossible de chercher dans le mapping
    if numero_tahiti.nil?
      Rails.logger.warn("Lexpol: compte de service demandé mais aucun SIRET fourni, utilisation de #{email}")
      return email
    end

    # Chercher dans le mapping SIRET → email de service
    service_email = APILexpol.service_emails[numero_tahiti]

    if service_email.nil?
      Rails.logger.warn("Lexpol: SIRET '#{numero_tahiti}' non trouvé dans LEXPOL_SERVICE_EMAILS, utilisation de #{email}")
    end

    service_email || email
  end

  def self.service_emails
    LEXPOL_SERVICE_EMAILS
  end

  def request_authentication
    options = { headers: { 'Content-Type' => 'application/json' } }
    body = { email_agent: @email_agent }

    if @use_certificate
      options[:sslcert] = ENV.fetch('LEXPOL_CERT_PATH')
      options[:sslkey] = ENV.fetch('LEXPOL_KEY_PATH')
    else
      body[:email] = ENV.fetch('LEXPOL_EMAIL')
      body[:motdepasse] = ENV.fetch('LEXPOL_PASSWORD')
    end

    options[:body] = body.to_json
    response = Typhoeus.post("#{BASE_URL}/authentification", options)
    return parse_token(response) if response.success?

    # pf: Lever une exception spécifique pour les problèmes de permissions
    if response.code == 401 || response.code == 403
      raise LexpolAccessDenied.new(@email_agent, response.code)
    end

    raise "Erreur d'authentification Lexpol : #{response.body}"
  end

  def request(method, endpoint, error_message, body = {})
    body[:jeton] = authenticate

    request = Typhoeus::Request.new("#{BASE_URL}#{endpoint}", request_options(body, method))
    response = request.run
    return parse_response(response, error_message) if response.success?

    # pf: Lever une exception spécifique pour les problèmes de permissions
    if response.code == 401 || response.code == 403
      raise LexpolAccessDenied.new(@email_agent, response.code)
    end

    raise "#{error_message} renvoi l'erreur HTML #{response.code}."
  end

  def request_options(body, method = :post)
    options = { method: }

    if @use_certificate
      options[:sslcert] = ENV.fetch('LEXPOL_CERT_PATH')
      options[:sslkey] = ENV.fetch('LEXPOL_KEY_PATH')
    end

    if method == :get
      options[:params] = body
    else
      options[:headers] = { 'Content-Type' => 'application/json' }
      options[:body] = body.to_json
    end

    options
  end

  def parse_token(response)
    JSON.parse(response.body)['jeton']
  end

  def parse_response(response, error_message)
    JSON.parse(response.body.force_encoding('UTF-8'))
  rescue JSON::ParserError
    raise "#{error_message} : impossible de lire la réponse de Lexpol"
  end
end
