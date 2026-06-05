# frozen_string_literal: true

# pf: supprime un champ de la révision brouillon (construction MCP).
module Mutations
  class DemarcheSupprimerChamp < Mutations::DemarcheChampMutation
    description "Supprimer un champ de la révision brouillon d'une démarche."

    argument :stable_id, String, "stable_id du champ à supprimer.", required: true

    def resolve(demarche:, stable_id:)
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      coordinate = procedure.draft_revision.remove_type_de_champ(stable_id)

      if coordinate.nil?
        { errors: ["Le champ \"#{stable_id}\" n'existe pas dans cette démarche."] }
      else
        { champ_stable_id: stable_id.to_s }
      end
    end
  end
end
