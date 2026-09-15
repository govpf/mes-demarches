# frozen_string_literal: true

# pf: pont entre l'arbre Logic d'une condition d'affichage et le format « plat » utilisé par
# le MCP (combinateur ET/OU + liste de termes champ source / opérateur / valeur). La table
# des opérateurs est partagée avec la mutation DemarcheDefinirCondition pour que ce que le
# MCP lit puisse être renvoyé tel quel à la mutation.
module Mcp
  class ConditionSerializer
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
      'hors_departement' => 'Logic::NotInDepartementOperator',
      'dans_region' => 'Logic::InRegionOperator',
      'hors_region' => 'Logic::NotInRegionOperator',
    }.freeze

    LOGIC_TO_OPERATEUR = OPERATEUR_TO_LOGIC.invert.freeze

    # Retourne nil si pas de condition, sinon { combinateur:, termes: [...] }.
    # Les termes vides (ligne non renseignée laissée par l'éditeur) sont ignorés.
    def self.to_h(condition, type_de_champs)
      return nil if condition.nil?

      combinateur, operands = case condition
      when Logic::Or then ['OU', condition.operands]
      when Logic::And then ['ET', condition.operands]
      else ['ET', [condition]]
      end

      termes = operands.filter_map { terme_h(_1, type_de_champs) }
      return nil if termes.empty?

      { combinateur:, termes: }
    end

    def self.terme_h(operand, type_de_champs)
      operateur = LOGIC_TO_OPERATEUR[operand.class.name]
      return nil if operateur.nil?
      return nil unless operand.left.is_a?(Logic::ChampValue)

      stable_id = operand.left.stable_id
      {
        champ_source_stable_id: stable_id.to_s,
        champ_source_libelle: type_de_champs.find { _1.stable_id == stable_id }&.libelle,
        operateur:,
        valeur: valeur_s(operand.right),
      }
    end

    def self.valeur_s(right)
      case right
      when Logic::Constant then right.value.to_s
      else ''
      end
    end
  end
end
