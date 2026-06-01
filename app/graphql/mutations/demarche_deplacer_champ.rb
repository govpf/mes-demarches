# frozen_string_literal: true

# pf: déplace un champ de la révision brouillon juste après un autre champ (construction MCP).
module Mutations
  class DemarcheDeplacerChamp < Mutations::DemarcheChampMutation
    description "Déplacer un champ de la révision brouillon juste après un autre champ."

    argument :stable_id, String, "stable_id du champ à déplacer.", required: true
    argument :apres_stable_id, String, "stable_id du champ après lequel placer le champ déplacé.", required: true

    def resolve(demarche:, stable_id:, apres_stable_id:)
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      draft = procedure.draft_revision

      source_coordinate, _ = draft.coordinate_and_tdc(stable_id)
      return { errors: ["Le champ \"#{stable_id}\" n'existe pas dans cette démarche."] } if source_coordinate.nil?

      target_coordinate, _ = draft.coordinate_and_tdc(apres_stable_id)
      return { errors: ["Le champ de destination \"#{apres_stable_id}\" n'existe pas."] } if target_coordinate.nil?

      draft.move_type_de_champ_after(stable_id, target_coordinate.position)
      { champ_stable_id: stable_id.to_s }
    end
  end
end
