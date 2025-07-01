# frozen_string_literal: true

class TableRowSelector::BaserowAPI
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

    def fetch_row(domain_id, row)
      return {} if row.to_i <= 0

      config = config(domain_id)
      response = Typhoeus.get(row_url(config['Table'], row), headers: database_headers(config['Token']))
      if response.success?
        model = fields(config)
        usager_fields = field_names(model, config['Champs usager'])
        instructeur_fields = field_names(model, config['Champs instructeur'])
        row = JSON.parse(response.body).filter { |name, _| name.start_with?('field_') }.transform_keys do |key|
          model[key[6..-1].to_i]
        end
        { usager_fields:, instructeur_fields:, row: }
      end
    end

    def field_names(model, field_ids)
      field_ids&.split(/,/)&.map(&:strip)&.map { model[_1.to_i] } || []
    end

    def config(row_id)
      response = Typhoeus.get(row_url(secrets[:config_table], row_id), headers: config_database_headers, params: default_params)
      response.success? ? JSON.parse(response.body) : nil
    end

    def fields(config)
      response = Typhoeus.get(list_database_table_fields(config['Table']), headers: database_headers(config['Token']))
      if response.success?
        JSON.parse(response.body).map { [_1['id'], _1['name']] }.to_h
      end
    end

    def rows_url(table_id) = "#{secrets[:url]}/api/database/rows/table/#{table_id}/"

    def row_url(table_id, row_id) = "#{rows_url(table_id)}#{row_id}/"

    def list_database_table_fields(table_id) = "#{secrets[:url]}/api/database/fields/table/#{table_id}/"

    def config_database_headers = database_headers(secrets[:token])

    def database_headers(token) = { 'Authorization' => "Token #{token}" }

    def default_params = { user_field_names: true }

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
        { label: result[:"field_#{search_field}"], value: "#{domain_id}:#{result[:id]}" }
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
