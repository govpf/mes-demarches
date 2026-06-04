# frozen_string_literal: true

# pf: lit les colonnes Baserow + le mapping courant d'un champ referentiel_de_polynesie,
# pour le serveur MCP (lecture seule).
module Resolvers
  module Mcp
    class ReferentielChampConfig < GraphQL::Schema::Resolver
      type Types::Mcp::ReferentielChampConfigType, null: false

      argument :demarche, Types::DemarcheDescriptorType::FindDemarcheInput, "La démarche cible.", required: true
      argument :stable_id, String, "stable_id du champ référentiel.", required: true

      def resolve(demarche:, stable_id:)
        number = demarche.number.presence || ApplicationRecord.id_from_typed_id(demarche.id)
        procedure = Procedure.find_by(id: number)
        raise GraphQL::ExecutionError, "La démarche \"#{number}\" n'existe pas." if procedure.nil?
        raise GraphQL::ExecutionError, "Vous n'avez pas accès à la démarche \"#{number}\"." unless context.authorized_demarche?(procedure)

        coordinate, tdc = procedure.draft_revision.coordinate_and_tdc(stable_id)
        raise GraphQL::ExecutionError, "Le champ \"#{stable_id}\" n'existe pas." if coordinate.nil?
        raise GraphQL::ExecutionError, "Le champ \"#{tdc.libelle}\" n'est pas un référentiel de Polynésie." unless tdc.type_champ == 'referentiel_de_polynesie'

        service = ::Mcp::ReferentielMappingService.new(tdc)
        { table_id: tdc.table_id, colonnes: service.colonnes, mapping_actuel: service.mapping_actuel }
      rescue ::Mcp::ReferentielMappingService::BaserowIndisponible => e
        raise GraphQL::ExecutionError, e.message
      end
    end
  end
end
