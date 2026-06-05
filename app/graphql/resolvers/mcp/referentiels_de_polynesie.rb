# frozen_string_literal: true

# pf: liste les tables Baserow disponibles (référentiels actifs), pour le serveur MCP.
# Config globale Baserow — pas de scope démarche, mais token admin requis.
module Resolvers
  module Mcp
    class ReferentielsDePolynesie < GraphQL::Schema::Resolver
      type [Types::Mcp::ReferentielTableType], null: false

      def resolve
        # pf: appel de current_administrateur comme gate d'authentification — lève
        # GraphQL::ExecutionError si administrateur_id absent (token absent ou trop ancien).
        context.current_administrateur
        ::Mcp::ReferentielMappingService.tables_disponibles.map do |t|
          { id: t[:id].to_s, nom: t[:name] }
        end
      end
    end
  end
end
