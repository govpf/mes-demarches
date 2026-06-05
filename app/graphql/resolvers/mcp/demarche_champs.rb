# frozen_string_literal: true

# pf: liste les champs (publics + privés) de la révision brouillon d'une démarche, avec
# leur stable_id, pour le serveur MCP. Lecture seule ; autorisation par scope du token.
module Resolvers
  module Mcp
    class DemarcheChamps < GraphQL::Schema::Resolver
      type [Types::Mcp::ChampStructureType], null: false

      argument :demarche, Types::DemarcheDescriptorType::FindDemarcheInput, "La démarche cible.", required: true

      # pf: convertit formule_expression de {tdcNNN} → {Libellé} pour que Claude puisse
      # réutiliser / comprendre l'expression sans connaître les tokens internes.
      def readable_options(tdc, revision)
        opts = tdc.options || {}
        return opts unless tdc.formule? && opts['formule_expression'].present?

        opts.merge('formule_expression' => FormulaExpressionService.convert_to_libelles(opts['formule_expression'], revision))
      end

      def resolve(demarche:)
        number = demarche.number.presence || ApplicationRecord.id_from_typed_id(demarche.id)
        procedure = Procedure.find_by(id: number)
        raise GraphQL::ExecutionError, "La démarche \"#{number}\" n'existe pas." if procedure.nil?
        raise GraphQL::ExecutionError, "Vous n'avez pas accès à la démarche \"#{number}\"." unless context.authorized_demarche?(procedure)

        revision = procedure.draft_revision
        coordinates = revision.revision_types_de_champ
        by_id = coordinates.index_by(&:id)

        coordinates.map do |coordinate|
          tdc = coordinate.type_de_champ
          parent = coordinate.parent_id ? by_id[coordinate.parent_id] : nil
          {
            stable_id: tdc.stable_id.to_s,
            type_champ: tdc.type_champ,
            libelle: tdc.libelle,
            description: tdc.description,
            obligatoire: tdc.mandatory?,
            prive: coordinate.private?,
            parent_stable_id: parent&.type_de_champ&.stable_id&.to_s,
            position: coordinate.position,
            a_condition: tdc.condition.present?,
            options: readable_options(tdc, revision),
          }
        end
      end
    end
  end
end
