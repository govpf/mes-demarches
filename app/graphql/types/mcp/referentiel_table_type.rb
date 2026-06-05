# frozen_string_literal: true

module Types
  module Mcp
    class ReferentielTableType < Types::BaseObject
      graphql_name 'McpReferentielTable'
      field :id, String, "Identifiant Baserow de la table.", null: false
      field :nom, String, "Nom du référentiel.", null: false
    end
  end
end
