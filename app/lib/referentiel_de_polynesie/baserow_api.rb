# frozen_string_literal: true

class ReferentielDePolynesie::BaserowAPI
  TIMEOUT = 10 # pf: timeout en secondes pour les appels Baserow
  # pf: types Baserow plausibles pour un champ e-mail propriétaire (diagnostic, pas un blocage)
  EMAIL_LIKE_TYPES = ['email', 'text', 'formula'].freeze

  class << self
    def search(domain_id, term, drop_down_other: false)
      config = config(domain_id)
      search_field = config['Champ de recherche']
      params = build_search_filters(search_field, term)
      url = rows_url(config['Table'])
      response = Typhoeus.get(url, headers: database_headers(config['Token']), params: params, timeout: TIMEOUT)

      if response.success?
        results = parse_search_results(response.body, search_field, domain_id)
        append_other_option_if_needed(results, drop_down_other)
      else
        [{ label: response.body, value: Champs::DropDownListChamp::OTHER }]
      end
    end

    def available_tables
      response = Typhoeus.get(rows_url(ENV['API_BASEROW_CONFIG_TABLE']), headers: config_database_headers, params: default_params, timeout: TIMEOUT)
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
      response = Typhoeus.get(row_url(config['Table'], row_id), headers: database_headers(config['Token']), params: default_params, timeout: TIMEOUT)
      if response.success?
        response_data = JSON.parse(response.body)

        # Filtrer les champs techniques Baserow (id, order) et simplifier les valeurs complexes
        response_data
          .except('id', 'order')
          .transform_values { |v| simplify_value(v) }
      end
    end

    # pf: version enrichie de search pour le mode autocomplete inline — retourne label, value ET row_data
    # row_data est un hash plat { 'Nom' => 'Papeete', ... } à chiffrer côté controller
    # Note: on n'utilise PAS user_field_names=true dans la requête de recherche car Baserow exige alors
    # des noms de champs (strings) dans les filtres alors que build_search_filters utilise des IDs numériques.
    # On mappe les IDs vers les noms via le model fields() après réception.
    def search_with_data(domain_id, term, drop_down_other: false, scope: nil)
      config = config(domain_id)
      return [] unless config

      search_field_id = config['Champ de recherche']
      model = fields(config)

      params = build_search_filters(search_field_id, term, scope:)
      # pf: ni terme ni scope → ne jamais renvoyer la table entière (défense en profondeur)
      return [] if params.blank?

      url = rows_url(config['Table'])
      response = Typhoeus.get(url, headers: database_headers(config['Token']), params:, timeout: TIMEOUT)

      return [] unless response.success?

      results = JSON.parse(response.body, symbolize_names: true)[:results].map do |result|
        label = result[:"field_#{search_field_id}"].to_s
        row_data = result.except(:id, :order).each_with_object({}) do |(key, value), hash|
          field_id = key.to_s.delete_prefix('field_').to_i
          field_name = model&.dig(field_id, :name) || key.to_s
          hash[field_name] = simplify_value(value)
        end
        { label:, value: "#{domain_id}:#{result[:id]}", row_data: }
      end
      append_other_option_if_needed(results, drop_down_other)
    end

    # pf: retourne un hash plat { 'Nom' => 'Papeete', ... } pour le mode exact_match
    # Utilise un filtre Baserow `equal` (sans user_field_names pour que les IDs numériques fonctionnent),
    # puis récupère la ligne complète avec user_field_names=true via fetch_row.
    def find_by_exact_value(domain_id, term)
      config = config(domain_id)
      search_field = config['Champ de recherche']
      params = build_exact_match_filter(search_field, term)
      url = rows_url(config['Table'])
      response = Typhoeus.get(url, headers: database_headers(config['Token']), params:, timeout: TIMEOUT)

      return {} unless response.success?
      results = JSON.parse(response.body, symbolize_names: true)[:results]
      row_id = results&.first&.dig(:id)
      return {} unless row_id

      fetch_row(domain_id, row_id)
    end

    def field_names(model, field_ids)
      field_ids&.split(/,/)&.map(&:strip)&.map { model[_1.to_i]&.[](:name) } || []
    end

    def config(row_id)
      response = Typhoeus.get(row_url(ENV['API_BASEROW_CONFIG_TABLE'], row_id), headers: config_database_headers, params: default_params, timeout: TIMEOUT)
      response.success? ? JSON.parse(response.body) : nil
    end

    # pf: DLNUF (« Dites-le-nous une fois ») — lit la colonne « Champ propriétaire » de la table
    # méta. Invariant : id renseigné ⟺ mode DLNUF ; vide ⟺ catalogue.
    # Fail-closed : id renseigné mais champ introuvable → :invalid. Ne JAMAIS retomber sur nil
    # dans ce cas : des données personnelles seraient déclassées en liste publique.
    def dlnuf_config(domain_id)
      config = config(domain_id)
      return nil unless config

      owner_field_id = config['Champ propriétaire']
      return nil if owner_field_id.blank?

      field = fields(config)&.dig(owner_field_id.to_i)
      return :invalid if field.nil?

      unless field[:type].in?(EMAIL_LIKE_TYPES)
        Rails.logger.warn("ReferentielDePolynesie: le champ propriétaire #{owner_field_id} (référentiel #{domain_id}) est de type #{field[:type]}, pas un e-mail")
      end

      { field_id: owner_field_id.to_i, field_name: field[:name], field_type: field[:type] }
    end

    # pf: retourne { id => { name:, type: } } au lieu de { id => name }
    def fields(config)
      response = Typhoeus.get(list_database_table_fields(config['Table']), headers: database_headers(config['Token']), timeout: TIMEOUT)
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

    def rows_url(table_id) = "#{ENV['API_BASEROW_URL']}/api/database/rows/table/#{table_id}/"

    def row_url(table_id, row_id) = "#{rows_url(table_id)}#{row_id}/"

    def list_database_table_fields(table_id) = "#{ENV['API_BASEROW_URL']}/api/database/fields/table/#{table_id}/"

    def config_database_headers = database_headers(ENV['API_BASEROW_TOKEN'])

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
    # Note: accepte les clés string ET symbol (JSON.parse symbolize_names vs sans)
    def simplify_value(value)
      case value
      when Hash
        value['value'] || value[:value]
      when Array
        values = value.filter_map { |item| item.is_a?(Hash) ? (item['value'] || item[:value]) : item }
        values.length <= 1 ? values.first : values.join(', ')
      else
        value
      end
    end

    private

    def build_exact_match_filter(search_field, term)
      {
        "filters" => JSON.generate({
          "filter_type" => "AND",
          "filters" => [{ "field" => search_field.to_i, "type" => "equal", "value" => term }],
        }),
      }
    end

    def build_search_filters(search_field, term, scope: nil)
      filters = extract_search_words(term).map do |word|
        { "field" => search_field.to_i, "type" => "contains", "value" => word }
      end
      # pf: DLNUF — le filtre propriétaire est TOUJOURS appliqué quand un scope est présent ;
      # q ne fait que réduire à l'intérieur du périmètre (la sécurité tient quel que soit q)
      if scope.present?
        filters << { "field" => scope[:field_id], "type" => "equal", "value" => scope[:value] }
      end
      return {} if filters.empty?

      { "filters" => JSON.generate({ "filter_type" => "AND", "filters" => filters }) }
    end

    def extract_search_words(term)
      term.to_s.strip.split(/\s+/).compact_blank
    end

    def parse_search_results(response_body, search_field, domain_id)
      JSON.parse(response_body, symbolize_names: true)[:results].map do |result|
        {
          label: result[:"field_#{search_field}"].to_s,
          value: "#{domain_id}:#{result[:id]}",
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
