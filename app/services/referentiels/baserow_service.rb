# frozen_string_literal: true

class Referentiels::BaserowService
  include Dry::Monads[:result]

  attr_reader :referentiel

  def initialize(referentiel:)
    @referentiel = referentiel
  end

  # pf: retourne un hash plat { 'Nom' => 'Papeete', ... } (sans enveloppe row)
  # pf: format standard PF "domain_id:row_id" produit par BaserowAPI#parse_search_results / #search_with_data
  def call(external_id)
    if external_id.to_s.match?(/\A\d+:\d+\z/)
      domain_id, row_id = external_id.to_s.split(':')
      result = ReferentielDePolynesie::API.fetch_row(domain_id.to_i, row_id.to_i)

      if result.present? && result.is_a?(Hash) && result.keys.any?
        Success(result)
      else
        Failure(retryable: false, reason: StandardError.new('Row not found'), code: 404)
      end
    else
      Failure(retryable: false, reason: StandardError.new("Unsupported external_id: #{external_id.inspect}"), code: 400)
    end
  rescue StandardError => e
    Rails.logger.error("Referentiels::BaserowService error: #{e.class} - #{e.message}")
    Failure(retryable: false, reason: e, code: 500)
  end

  def validate_referentiel
    config = referentiel.baserow_config

    if config.blank?
      referentiel.update_column(:last_response, { 'status' => 404, 'body' => { 'error' => 'Config not found' } })
      return false
    end

    sample_row = fetch_sample_row(config)

    if sample_row.present?
      referentiel.update_column(:last_response, { 'status' => 200, 'body' => sample_row })
      true
    else
      referentiel.update_column(:last_response, { 'status' => 404, 'body' => { 'error' => 'No data in table' } })
      false
    end
  rescue StandardError => e
    Rails.logger.error("Referentiels::BaserowService validation error: #{e.class} - #{e.message}")
    referentiel.update_column(:last_response, { 'status' => 500, 'body' => { 'error' => e.message } })
    false
  end

  private

  # pf: retourne directement la sample row plate (sans enveloppe { 'row' => ... })
  # Si test_data contient un row ID, récupère cette ligne spécifique (données plus représentatives)
  # Sinon, fallback sur la première ligne de la table
  def fetch_sample_row(config)
    table_id = config['Table']
    token = config['Token']
    return nil unless table_id.present? && token.present?

    base_url = ENV['API_BASEROW_URL']
    headers = { 'Authorization' => "Token #{token}" }

    if referentiel.test_data.present?
      # pf: récupérer une ligne spécifique pour avoir des données représentatives (ex: champs Select remplis)
      url = "#{base_url}/api/database/rows/table/#{table_id}/#{referentiel.test_data}/?user_field_names=true"
      response = Typhoeus.get(url, headers:, timeout: ReferentielDePolynesie::BaserowAPI::TIMEOUT)
      return ReferentielDePolynesie::BaserowAPI.simplify_row(JSON.parse(response.body)) if response.success?
    end

    # Fallback : première ligne
    url = "#{base_url}/api/database/rows/table/#{table_id}/?user_field_names=true&size=1"
    response = Typhoeus.get(url, headers:, timeout: ReferentielDePolynesie::BaserowAPI::TIMEOUT)

    if response.success?
      data = JSON.parse(response.body)
      ReferentielDePolynesie::BaserowAPI.simplify_row(data['results']&.first)
    end
  rescue StandardError => e
    Rails.logger.error("BaserowService fetch_sample_row error: #{e.class} - #{e.message}")
    nil
  end
end
