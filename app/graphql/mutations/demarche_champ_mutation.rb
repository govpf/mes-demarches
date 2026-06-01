# frozen_string_literal: true

# pf: classe de base des mutations MCP de construction de structure de démarche.
# Factorise l'argument `demarche`, le format de retour, et la résolution + autorisation
# de la procédure. Le contrôle `write_access` du token est assuré par BaseMutation#ready?.
module Mutations
  class DemarcheChampMutation < Mutations::BaseMutation
    argument :demarche, Types::DemarcheDescriptorType::FindDemarcheInput, "La démarche cible.", required: true

    field :champ_stable_id, String, "Le stable_id du champ concerné.", null: true
    field :errors, [Types::ValidationErrorType], null: true

    private

    # Retourne [procedure, nil] si autorisée, sinon [nil, "message d'erreur"].
    def find_authorized_procedure(demarche)
      number = demarche.number.presence || ApplicationRecord.id_from_typed_id(demarche.id)
      procedure = Procedure.find_by(id: number)

      return [nil, "La démarche \"#{number}\" n'existe pas."] if procedure.nil?
      return [nil, "Vous n'avez pas accès à la démarche \"#{number}\"."] unless context.authorized_demarche?(procedure)

      [procedure, nil]
    end
  end
end
