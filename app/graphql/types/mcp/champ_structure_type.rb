# frozen_string_literal: true

# pf: structure simplifiée d'un champ, exposée au serveur MCP (avec le stable_id que les
# mutations de construction attendent — l'id global de ChampDescriptor ne convient pas).
module Types
  module Mcp
    class ChampStructureType < Types::BaseObject
      graphql_name 'McpChampStructure'

      field :stable_id, String, null: false
      field :type_champ, String, null: false
      field :libelle, String, null: false
      field :description, String, null: true
      field :obligatoire, Boolean, null: false
      field :prive, Boolean, null: false
      field :parent_stable_id, String, null: true
      field :position, Integer, null: false
      field :a_condition, Boolean, null: false
    end
  end
end
