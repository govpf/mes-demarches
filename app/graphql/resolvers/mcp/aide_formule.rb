# frozen_string_literal: true

# pf: renvoie la documentation IA d'écriture de formule pour un champ formule donné
# (réutilise FormulaAiPromptService : variables référençables, fonctions, syntaxe). Pour le MCP.
module Resolvers
  module Mcp
    class AideFormule < GraphQL::Schema::Resolver
      type String, null: false

      argument :demarche, Types::DemarcheDescriptorType::FindDemarcheInput, "La démarche cible.", required: true
      argument :stable_id, String, "stable_id du champ formule.", required: true

      def resolve(demarche:, stable_id:)
        number = demarche.number.presence || ApplicationRecord.id_from_typed_id(demarche.id)
        procedure = Procedure.find_by(id: number)
        raise GraphQL::ExecutionError, "La démarche \"#{number}\" n'existe pas." if procedure.nil?
        raise GraphQL::ExecutionError, "Vous n'avez pas accès à la démarche \"#{number}\"." unless context.authorized_demarche?(procedure)

        coordinate, type_de_champ = procedure.draft_revision.coordinate_and_tdc(stable_id)
        raise GraphQL::ExecutionError, "Le champ \"#{stable_id}\" n'existe pas dans cette démarche." if coordinate.nil?
        raise GraphQL::ExecutionError, "Le champ \"#{type_de_champ.libelle}\" n'est pas un champ formule." unless type_de_champ.formule?

        FormulaAiPromptService.new(type_de_champ: type_de_champ, coordinate: coordinate).generate
      end
    end
  end
end
