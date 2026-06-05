# frozen_string_literal: true

# pf: table de référentiel Baserow disponible, exposée au MCP pour le choix du table_id.
module Types
  module Mcp
    class ReferentielTableType < Types::BaseObject
      graphql_name 'McpReferentielTable'
      field :id, String, "Identifiant Baserow de la table.", null: false
      field :nom, String, "Nom du référentiel.", null: false
    end
  end
end
