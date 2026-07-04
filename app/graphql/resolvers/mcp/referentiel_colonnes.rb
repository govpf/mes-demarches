# frozen_string_literal: true

# pf: colonnes d'une table Baserow (pour le serveur MCP). Pas de scope démarche —
# config globale Baserow — mais token admin requis.
module Resolvers
  module Mcp
    class ReferentielColonnes < GraphQL::Schema::Resolver
      type [Types::Mcp::ReferentielColonneType], null: false

      argument :table_id, String, "Identifiant Baserow de la table.", required: true

      def resolve(table_id:)
        # pf: gate d'authentification — lève GraphQL::ExecutionError si pas d'admin
        context.current_administrateur
        ::Mcp::ReferentielMappingService.colonnes_pour_table(table_id)
      rescue ::Mcp::ReferentielMappingService::BaserowIndisponible => e
        raise GraphQL::ExecutionError, e.message
      end
    end
  end
end
