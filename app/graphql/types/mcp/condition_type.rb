# frozen_string_literal: true

# pf: condition d'affichage d'un champ, dans le format « plat » du MCP.
module Types
  module Mcp
    class ConditionType < Types::BaseObject
      graphql_name 'McpCondition'
      description "Condition d'affichage d'un champ : combinateur ET/OU et liste de termes, réutilisable telle quelle dans la mutation demarcheDefinirCondition."

      field :combinateur, String, "ET ou OU.", null: false
      field :termes, [Types::Mcp::ConditionTermeType], null: false
    end
  end
end
