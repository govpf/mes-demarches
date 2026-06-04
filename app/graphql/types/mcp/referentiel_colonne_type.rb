# frozen_string_literal: true

module Types
  module Mcp
    class ReferentielColonneType < Types::BaseObject
      graphql_name 'McpReferentielColonne'
      field :nom, String, null: false
      field :type_mapping, String, "Type interne (string, integer_number, decimal_number, boolean, date, array).", null: false
    end
  end
end
