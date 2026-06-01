# frozen_string_literal: true

# pf: modifie un champ existant de la révision brouillon (construction MCP).
module Mutations
  class DemarcheModifierChamp < Mutations::DemarcheChampMutation
    description "Modifier un champ existant de la révision brouillon d'une démarche."

    argument :stable_id, String, "stable_id du champ à modifier.", required: true
    argument :libelle, String, required: false
    argument :description, String, required: false
    argument :obligatoire, Boolean, required: false
    argument :type_champ, String, "Nouveau type. Restreint aux types compatibles si le champ est déjà publié.", required: false

    def resolve(demarche:, stable_id:, libelle: nil, description: nil, obligatoire: nil, type_champ: nil)
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      draft = procedure.draft_revision
      coordinate, current_tdc = draft.coordinate_and_tdc(stable_id)
      return { errors: ["Le champ \"#{stable_id}\" n'existe pas dans cette démarche."] } if coordinate.nil?

      if type_champ.present? && type_champ != current_tdc.type_champ
        return { errors: ["Type de champ inconnu : \"#{type_champ}\"."] } unless TypeDeChamp.type_champs.key?(type_champ)

        # pf: on RÉUTILISE (sans la refactorer ni la déplacer) la logique de l'éditeur upstream
        # qui détermine les types cibles compatibles, via sa constante publique ACCEPTED_TYPES
        # (dérivée de Columns::ChampColumn::CAST) + les garde-fous routage/éligibilité de la
        # coordonnée. Si upstream fait évoluer la matrice, le MCP en bénéficie automatiquement.
        if coordinate.used_by_routing_rules? || coordinate.used_by_ineligibilite_rules?
          return { errors: ["Le type de ce champ n'est pas modifiable : il est utilisé par une règle de routage ou d'éligibilité."] }
        end

        published_type_champ = procedure.published_revision
          &.types_de_champ&.find { _1.stable_id.to_s == stable_id.to_s }&.type_champ

        if published_type_champ.present?
          accepted = [published_type_champ] + TypesDeChampEditor::ChampComponent::ACCEPTED_TYPES.fetch(published_type_champ, [])
          unless accepted.map(&:to_s).include?(type_champ.to_s)
            return { errors: ["Ce champ est déjà publié : son type ne peut être changé que vers un type compatible (#{accepted.join(', ')}), pour préserver les dossiers existants."] }
          end
        end
      end

      attrs = {}
      attrs[:libelle] = libelle unless libelle.nil?
      attrs[:description] = description unless description.nil?
      attrs[:mandatory] = obligatoire unless obligatoire.nil?
      attrs[:type_champ] = type_champ unless type_champ.nil?
      return { errors: ["Aucune modification fournie."] } if attrs.empty?

      type_de_champ = draft.find_and_ensure_exclusive_use(stable_id)

      if type_de_champ.update(attrs)
        { champ_stable_id: stable_id.to_s }
      else
        { errors: type_de_champ.errors.full_messages }
      end
    end
  end
end
