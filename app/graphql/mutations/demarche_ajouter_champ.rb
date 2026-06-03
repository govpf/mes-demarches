# frozen_string_literal: true

# pf: ajoute un type de champ à la révision brouillon d'une démarche (construction MCP).
module Mutations
  class DemarcheAjouterChamp < Mutations::DemarcheChampMutation
    description "Ajouter un champ à la révision brouillon d'une démarche."

    argument :type_champ, String, "Type du champ (ex: text, email, integer_number, header_section, repetition…).", required: true
    argument :libelle, String, "Libellé du champ.", required: true
    argument :description, String, required: false
    argument :obligatoire, Boolean, required: false, default_value: false
    argument :prive, Boolean, "Annotation privée (instructeur) plutôt que champ usager.", required: false, default_value: false
    argument :parent_stable_id, String, "Pour insérer dans une répétition/bloc.", required: false
    argument :apres_stable_id, String, "Insérer juste après ce champ (sinon en tête).", required: false
    argument :options, Types::OptionsBlob, "Options spécifiques au type (ex. { drop_down_options: [...] }).", required: false

    def resolve(demarche:, type_champ:, libelle:, description: nil, obligatoire: false, prive: false, parent_stable_id: nil, apres_stable_id: nil, options: nil)
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      return { errors: ["Type de champ inconnu : \"#{type_champ}\"."] } unless TypeDeChamp.type_champs.key?(type_champ)

      draft = procedure.draft_revision

      if parent_stable_id.present? && draft.coordinate_and_tdc(parent_stable_id).first.nil?
        return { errors: ["Le champ parent \"#{parent_stable_id}\" n'existe pas dans cette démarche."] }
      end

      if apres_stable_id.present? && draft.coordinate_and_tdc(apres_stable_id).first.nil?
        return { errors: ["Le champ \"#{apres_stable_id}\" (après lequel insérer) n'existe pas dans cette démarche."] }
      end

      params = { type_champ:, libelle:, mandatory: obligatoire, private: prive }
      params[:description] = description if description.present?
      params[:parent_stable_id] = parent_stable_id if parent_stable_id.present?
      params[:after_stable_id] = apres_stable_id if apres_stable_id.present?

      type_de_champ = draft.add_type_de_champ(params)

      return { errors: type_de_champ.errors.full_messages } unless type_de_champ.valid?

      if options.present?
        error = appliquer_options!(type_de_champ, options)
        return { errors: [error] } if error
        return { errors: type_de_champ.errors.full_messages } unless type_de_champ.save
      end

      { champ_stable_id: type_de_champ.stable_id.to_s }
    end
  end
end
