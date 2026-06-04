# frozen_string_literal: true

module Types
  module Mcp
    class ReferentielChampConfigType < Types::BaseObject
      graphql_name 'McpReferentielChampConfig'
      field :table_id, String, null: true
      field :colonnes, [Types::Mcp::ReferentielColonneType], null: false
      field :mapping_actuel, Types::OptionsBlob, "Mapping courant (par colonne).", null: false
    end
  end
end
