# frozen_string_literal: true

module Types::Champs
  class TableRowSelectorChampType < Types::BaseObject
    implements Types::ChampType

    field :columns, [Types::Champs::ReferentielDePolynesieChampType::TableColumnType], null: false, description: "Colonnes et valeurs de la table externe"
    field :external_id, String, null: true, description: "Identifiant externe de l'enregistrement dans la source de données"

    def columns
      return [] if object.data.blank?

      data = object.data.is_a?(String) ? JSON.parse(object.data) : object.data
      return [] unless data.is_a?(Hash) && data.key?('row')
      
      # Utiliser instructeur_fields pour déterminer quelles colonnes afficher
      fields = data['instructeur_fields'].presence || data['row'].keys
      row = data['row']
      
      fields.map do |field_name|
        value = row.key?(field_name) ? (row[field_name] || "") : "Champ #{field_name} inconnu"
        {
          name: field_name,
          value: format_value_for_api(value),
          type: infer_type(value)
        }
      end
    rescue JSON::ParserError
      []
    end

    def external_id
      return nil if object.data.blank?

      data = object.data.is_a?(String) ? JSON.parse(object.data) : object.data
      data['external_id']
    rescue JSON::ParserError
      nil
    end

    private

    def format_value_for_api(value)
      case value
      when TrueClass, FalseClass
        value.to_s
      when String
        value
      when Array
        # Pour une API GraphQL, on convertit en string lisible
        value.map do |item|
          if item.is_a?(Hash)
            if item['value']
              item['value']
            elsif item['url'] && item['visible_name']
              "#{item['visible_name']} (#{item['url']})"
            else
              item.inspect
            end
          else
            item.to_s
          end
        end.join(', ')
      when Hash
        # Pour une API GraphQL, on extrait la valeur principale ou convertit en string
        if value['value']
          value['value'].to_s
        elsif value['url'] && value['visible_name']
          "#{value['visible_name']} (#{value['url']})"
        else
          value.inspect
        end
      when Numeric
        value.to_s
      when NilClass
        ""
      else
        value.to_s
      end
    end

    def infer_type(value)
      case value
      when Numeric
        "number"
      when TrueClass, FalseClass
        "boolean"
      when String
        "string"
      when Array
        "array"
      when Hash
        "object"
      else
        "unknown"
      end
    end
  end
end
