# frozen_string_literal: true

# pf: pose ou retire la condition d'affichage d'un champ de la révision brouillon (construction MCP).
# Construit l'arbre Logic directement (constructeurs de classe) et réutilise le validateur
# intégré `condition.errors(source_tdcs)`. La source d'une condition est limitée aux champs
# situés en amont (upper_coordinates), comme dans l'éditeur.
module Mutations
  class DemarcheDefinirCondition < Mutations::DemarcheChampMutation
    description "Définir (ou retirer) la condition d'affichage d'un champ de la révision brouillon."

    OPERATEUR_TO_LOGIC = {
      'egal' => 'Logic::Eq',
      'different' => 'Logic::NotEq',
      'superieur' => 'Logic::GreaterThan',
      'superieur_ou_egal' => 'Logic::GreaterThanEq',
      'inferieur' => 'Logic::LessThan',
      'inferieur_ou_egal' => 'Logic::LessThanEq',
      'inclut' => 'Logic::IncludeOperator',
      'exclut' => 'Logic::ExcludeOperator',
      'dans_archipel' => 'Logic::InArchipelOperator',
      'hors_archipel' => 'Logic::NotInArchipelOperator',
      'dans_departement' => 'Logic::InDepartementOperator',
      'dans_region' => 'Logic::InRegionOperator',
    }.freeze

    argument :stable_id, String, "stable_id du champ dont on définit la condition d'affichage.", required: true
    argument :combinateur, String, "ET ou OU pour combiner plusieurs termes (défaut : ET).", required: false, default_value: 'ET'
    argument :termes, [Types::ConditionTermeInput], "Termes de la condition. Liste vide => retire la condition.", required: true

    def resolve(demarche:, stable_id:, termes:, combinateur: 'ET')
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      draft = procedure.draft_revision
      coordinate, _ = draft.coordinate_and_tdc(stable_id)
      return { errors: ["Le champ \"#{stable_id}\" n'existe pas dans cette démarche."] } if coordinate.nil?

      type_de_champ = draft.find_and_ensure_exclusive_use(stable_id)
      coordinate = draft.coordinate_for(type_de_champ)
      source_tdcs = coordinate.upper_coordinates.map(&:type_de_champ)

      if termes.empty?
        type_de_champ.update!(condition: nil)
        return { champ_stable_id: stable_id.to_s }
      end

      sub_conditions = []
      termes.each do |terme|
        operator_class_name = OPERATEUR_TO_LOGIC[terme.operateur]
        if operator_class_name.nil?
          return { errors: ["Opérateur inconnu : \"#{terme.operateur}\". Valeurs acceptées : #{OPERATEUR_TO_LOGIC.keys.join(', ')}."] }
        end

        # pf: garde explicite sur la source — ChampValue#type retourne :unmanaged si absent de
        # source_tdcs, mais la cascade d'erreurs dépend de l'opérateur ; mieux vaut signaler
        # clairement que la source n'est pas en amont.
        unless source_tdcs.map { _1.stable_id.to_s }.include?(terme.champ_source_stable_id)
          return { errors: ["Le champ source (stable_id #{terme.champ_source_stable_id}) n'est pas situé avant le champ conditionné."] }
        end

        left = Logic::ChampValue.new(terme.champ_source_stable_id.to_i)
        right = coerce_constant(left, terme.valeur, source_tdcs)
        sub_conditions << Logic.class_from_name(operator_class_name).new(left, right)
      end

      condition = if sub_conditions.one?
        sub_conditions.first
      elsif combinateur == 'OU'
        Logic::Or.new(sub_conditions)
      else
        Logic::And.new(sub_conditions)
      end

      condition_errors = condition.errors(source_tdcs)
      return { errors: condition_errors.map { humanize_condition_error(_1) } } if condition_errors.present?

      type_de_champ.update!(condition:)
      { champ_stable_id: stable_id.to_s }
    end

    private

    # pf: reproduit la coercition de ConditionForm#parse_value (format d'entrée différent).
    def coerce_constant(left, valeur, source_tdcs)
      case left.type(source_tdcs)
      when :boolean
        Logic::Constant.new(ActiveModel::Type::Boolean.new.cast(valeur))
      when :number
        number = Float(valeur) rescue nil
        Logic::Constant.new(number.nil? ? valeur : (number % 1 == 0 ? number.to_i : number))
      else
        Logic::Constant.new(valeur)
      end
    end

    def humanize_condition_error(err)
      return err if err.is_a?(String)

      case err[:type]
      when :not_available, :unmanaged
        "Le champ source (stable_id #{err[:stable_id]}) doit être un champ situé avant le champ conditionné."
      when :incompatible
        "La valeur n'est pas compatible avec le type du champ source (stable_id #{err[:stable_id]})."
      when :not_included
        "La valeur ne fait pas partie des options du champ source (stable_id #{err[:stable_id]})."
      when :empty_options
        "Le champ source (stable_id #{err[:stable_id]}) n'a pas d'options configurées."
      when :required_number
        "L'opérateur « #{err[:operator_name]} » requiert des nombres des deux côtés."
      when :required_include
        "Pour un champ à choix multiples, utilisez l'opérateur « inclut » ou « exclut »."
      else
        "Condition invalide (#{err[:type]})."
      end
    end
  end
end
