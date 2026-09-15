# frozen_string_literal: true

# pf: un terme d'une condition d'affichage lu via le MCP (miroir de ConditionTermeInput).
module Types
  module Mcp
    class ConditionTermeType < Types::BaseObject
      graphql_name 'McpConditionTerme'
      description "Un terme d'une condition d'affichage, dans le format attendu par la mutation demarcheDefinirCondition."

      field :champ_source_stable_id, String, "stable_id du champ source.", null: false
      field :champ_source_libelle, String, "Libellé du champ source (null si le champ a été supprimé de la révision).", null: true
      field :operateur, String, "Opérateur : egal | different | superieur | superieur_ou_egal | inferieur | inferieur_ou_egal | inclut | exclut | dans_archipel | hors_archipel | dans_departement | hors_departement | dans_region | hors_region", null: false
      field :valeur, String, "Valeur comparée, sous forme de chaîne ('true'/'false' pour un booléen).", null: false
    end
  end
end
