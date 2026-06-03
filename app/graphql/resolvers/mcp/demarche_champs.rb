# frozen_string_literal: true

# pf: liste les champs (publics + privés) de la révision brouillon d'une démarche, avec
# leur stable_id, pour le serveur MCP. Lecture seule ; autorisation par scope du token.
module Resolvers
  module Mcp
    class DemarcheChamps < GraphQL::Schema::Resolver
      type [Types::Mcp::ChampStructureType], null: false

      argument :demarche, Types::DemarcheDescriptorType::FindDemarcheInput, "La démarche cible.", required: true

      def resolve(demarche:)
        number = demarche.number.presence || ApplicationRecord.id_from_typed_id(demarche.id)
        procedure = Procedure.find_by(id: number)
        raise GraphQL::ExecutionError, "La démarche \"#{number}\" n'existe pas." if procedure.nil?
        raise GraphQL::ExecutionError, "Vous n'avez pas accès à la démarche \"#{number}\"." unless context.authorized_demarche?(procedure)

        procedure.draft_revision.revision_types_de_champ.map do |coordinate|
          tdc = coordinate.type_de_champ
          {
            stable_id: tdc.stable_id.to_s,
            type_champ: tdc.type_champ,
            libelle: tdc.libelle,
            description: tdc.description,
            obligatoire: tdc.mandatory?,
            prive: coordinate.private?,
            parent_stable_id: coordinate.parent&.stable_id&.to_s,
            position: coordinate.position,
            a_condition: tdc.condition.present?,
          }
        end
      end
    end
  end
end
