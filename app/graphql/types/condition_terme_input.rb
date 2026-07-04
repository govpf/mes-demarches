# frozen_string_literal: true

# pf: un terme d'une condition d'affichage construite via le MCP.
module Types
  class ConditionTermeInput < Types::BaseInputObject
    description "Un terme d'une condition d'affichage : champ source + opérateur + valeur."

    argument :champ_source_stable_id, String, "stable_id du champ source (doit être situé AVANT le champ conditionné).", required: true
    argument :operateur, String, "egal | different | superieur | superieur_ou_egal | inferieur | inferieur_ou_egal | inclut | exclut | dans_archipel | hors_archipel | dans_departement | dans_region", required: true
    argument :valeur, String, "Valeur comparée. Booléen : 'true'/'false'. Nombre : '18'. Liste : le libellé d'option.", required: true
  end
end
