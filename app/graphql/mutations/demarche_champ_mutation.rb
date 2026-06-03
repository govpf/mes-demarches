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

    # pf: valide + normalise + applique un blob d'options sur un type de champ.
    # Réutilise TypeDeChamp::OPTS_BY_TYPE (map canonique, options standard + PF) pour
    # rejeter toute clé non autorisée. Retourne nil si OK, ou un message d'erreur.
    # N'applique que sur le tdc (en mémoire) ; l'appelant doit sauvegarder.
    def appliquer_options!(type_de_champ, options)
      return nil if options.blank?

      unless options.is_a?(Hash)
        return "Le paramètre « options » doit être un objet JSON (clé/valeur), reçu : #{options.class}."
      end

      allowed = TypeDeChamp::OPTS_BY_TYPE.fetch(type_de_champ.type_champ) { [] }.map(&:to_s)
      unknown = options.keys.map(&:to_s) - allowed
      if unknown.any?
        return "Options non autorisées pour le type « #{type_de_champ.type_champ} » : #{unknown.join(', ')}." \
               " Options valides : #{allowed.empty? ? '(aucune)' : allowed.join(', ')}."
      end

      normalized = options.to_h.to_h do |key, value|
        normalized_value = case value
        when true then '1'
        when false then '0'
        when Numeric then value.to_s
        else value
        end
        [key.to_s, normalized_value]
      end

      type_de_champ.editable_options = normalized
      nil
    end
  end
end
