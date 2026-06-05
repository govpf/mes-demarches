# frozen_string_literal: true

module Types
  module Mcp
    class ReferentielChampConfigType < Types::BaseObject
      graphql_name 'McpReferentielChampConfig'
      field :table_id, String, null: true
      field :colonnes, [Types::Mcp::ReferentielColonneType], null: false
      field :mapping_actuel, Types::OptionsBlob, "Mapping courant (par colonne).", null: false
      field :mode, String, "Mode de saisie (autocomplete ou exact_match).", null: true
      field :hint, String, "Indications de saisie affichées à l'usager.", null: true
    end
  end
end
