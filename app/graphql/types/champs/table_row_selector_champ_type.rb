# frozen_string_literal: true

module Types::Champs
  class TableRowSelectorChampType < Types::BaseObject
    implements Types::ChampType

    class TableColumnType < Types::BaseObject
      field :name, String, null: false, description: "Nom de la colonne"
      field :value, String, null: true, description: "Valeur de la colonne"
      field :type, String, null: false, description: "Type de la valeur"
    end

    field :columns, [TableColumnType], null: false, description: "Colonnes et valeurs de la table externe"

    def columns
      return [] if object.data.blank?

      data = object.data.is_a?(String) ? JSON.parse(object.data) : object.data
      data.map do |key, value|
        {
          name: key,
          value: value.to_s,
          type: infer_type(value)
        }
      end
    rescue JSON::ParserError
      []
    end

    private

    def infer_type(value)
      case value
      when Numeric
        "number"
      when TrueClass, FalseClass
        "boolean"
      when String
        "string"
      else
        "unknown"
      end
    end
  end
end
