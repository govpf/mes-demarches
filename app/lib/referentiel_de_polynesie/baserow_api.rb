# frozen_string_literal: true

class ReferentielDePolynesie::BaserowAPI
  class << self
    def secrets = Rails.application.secrets.baserow

    def search(domain_id, term, drop_down_other: false)
      config = config(domain_id)
      search_field = config['Champ de recherche']
      params = build_search_filters(search_field, term)
      url = rows_url(config['Table'])
      response = Typhoeus.get(url, headers: database_headers(config['Token']), params: params)

      if response.success?
        results = parse_search_results(response.body, search_field, domain_id)
        append_other_option_if_needed(results, drop_down_other)
      else
        [{ label: response.body, value: Champs::DropDownListChamp::OTHER }]
      end
    end

    def available_tables
      response = Typhoeus.get(rows_url(secrets[:config_table]), headers: config_database_headers, params: default_params)
      if response.success?
        JSON.parse(response.body, symbolize_names: true)[:results]&.filter { _1[:Actif] }&.map do
          { name: _1[:Nom], id: _1[:id] }
        end
      end
    end

    # pf: retourne un hash plat { 'Nom' => 'Papeete', 'Code' => '98714' } (sans enveloppe row/usager_fields)
    # Les valeurs complexes Baserow (single_select, link_row) sont simplifiées en valeurs lisibles
    # Utilise user_field_names=true pour que Baserow retourne directement les noms de colonnes comme clés
    def fetch_row(domain_id, row_id)
      return {} if row_id.to_i <= 0

      config = config(domain_id)
      response = Typhoeus.get(row_url(config['Table'], row_id), headers: database_headers(config['Token']), params: default_params)
      if response.success?
        response_data = JSON.parse(response.body)

        # Filtrer les champs techniques Baserow (id, order) et simplifier les valeurs complexes
        response_data
          .except('id', 'order')
          .transform_values { |v| simplify_value(v) }
      end
    end

    def field_names(model, field_ids)
      field_ids&.split(/,/)&.map(&:strip)&.map { model[_1.to_i]&.[](:name) } || []
    end

    def config(row_id)
      response = Typhoeus.get(row_url(secrets[:config_table], row_id), headers: config_database_headers, params: default_params)
      response.success? ? JSON.parse(response.body) : nil
    end

    # pf: retourne { id => { name:, type: } } au lieu de { id => name }
    def fields(config)
      response = Typhoeus.get(list_database_table_fields(config['Table']), headers: database_headers(config['Token']))
      if response.success?
        JSON.parse(response.body).map { [_1['id'], { name: _1['name'], type: _1['type'] }] }.to_h
      end
    end

    # pf: convertit un type Baserow en type de mapping upstream
    def baserow_type_to_mapping_type(field_metadata)
      baserow_type = field_metadata['type'] || field_metadata[:type]
      case baserow_type
      when 'number'
        decimal_places = field_metadata['number_decimal_places'] || field_metadata[:number_decimal_places] || 0
        decimal_places.to_i > 0 ? 'decimal_number' : 'integer_number'
      when 'date' then 'date'
      when 'boolean' then 'boolean'
      when 'multiple_select' then 'array'
      else 'string' # text, long_text, email, url, phone_number, single_select, formula, lookup, link_row...
      end
    end

    def rows_url(table_id) = "#{secrets[:url]}/api/database/rows/table/#{table_id}/"

    def row_url(table_id, row_id) = "#{rows_url(table_id)}#{row_id}/"

    def list_database_table_fields(table_id) = "#{secrets[:url]}/api/database/fields/table/#{table_id}/"

    def config_database_headers = database_headers(secrets[:token])

    def database_headers(token) = { 'Authorization' => "Token #{token}" }

    def default_params = { user_field_names: true }

    # pf: simplifie les valeurs complexes d'un row Baserow retourné avec user_field_names=true
    # Utilisé par BaserowService#fetch_sample_row pour les données de test
    def simplify_row(row)
      return row unless row.is_a?(Hash)

      row.transform_values { |v| simplify_value(v) }
    end

    # pf: simplifie une valeur Baserow complexe en valeur lisible
    # - single_select { "id" => 1, "value" => "Cat", "color" => "red" } → "Cat"
    # - link_row [{ "id" => 1, "value" => "X" }] → "X" (ou "X, Y" si multi)
    # - multiple_select [{ "id" => 1, "value" => "A" }, ...] → "A, B"
    # - nil, strings, numbers → inchangés
    def simplify_value(value)
      case value
      when Hash
        value['value']
      when Array
        values = value.filter_map { |item| item.is_a?(Hash) ? item['value'] : item }
        values.length <= 1 ? values.first : values.join(', ')
      else
        value
      end
    end

    private

    def build_search_filters(search_field, term)
      words = extract_search_words(term)
      return {} if words.empty?

      if words.size == 1
        build_single_word_filter(search_field, words.first)
      else
        build_multi_word_filters(search_field, words)
      end
    end

    def extract_search_words(term)
      term.to_s.strip.split(/\s+/).compact_blank
    end

    def build_single_word_filter(search_field, word)
      {
        "filters" => JSON.generate({
          "filter_type" => "AND",
          "filters" => [
            {
              "field" => search_field.to_i,
              "type" => "contains",
              "value" => word
            }
          ]
        })
      }
    end

    def build_multi_word_filters(search_field, words)
      filters = words.map do |word|
        {
          "field" => search_field.to_i,
          "type" => "contains",
          "value" => word
        }
      end

      {
        "filters" => JSON.generate({
          "filter_type" => "AND",
          "filters" => filters
        })
      }
    end

    def parse_search_results(response_body, search_field, domain_id)
      JSON.parse(response_body, symbolize_names: true)[:results].map do |result|
        {
          label: result[:"field_#{search_field}"].to_s,
          value: "#{domain_id}:#{result[:id]}"
        }
      end
    end

    def append_other_option_if_needed(results, drop_down_other)
      if drop_down_other
        results << { label: I18n.t('shared.champs.drop_down_list.other'), value: Champs::DropDownListChamp::OTHER }
      end
      results
    end
  end
end
