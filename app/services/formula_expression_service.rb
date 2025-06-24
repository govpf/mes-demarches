# frozen_string_literal: true

class FormulaExpressionService
  class << self
    def convert_to_stable_ids(expression, revision)
      return ['', []] if expression.blank?

      dependencies = []
      stable_expression = expression.gsub(/\{([^}]+)\}/) do |match|
        libelle = $1.strip
        tdc = find_type_de_champ_by_libelle(libelle, revision)

        if tdc
          dependencies << tdc.stable_id
          "{#{tdc.stable_id}}"
        else
          match # Garde l'original si pas trouvé
        end
      end

      [stable_expression, dependencies.uniq]
    end

    def convert_to_libelles(stable_expression, revision)
      return '' if stable_expression.blank?

      stable_expression.gsub(/\{(\d+)\}/) do |match|
        stable_id = $1.to_i
        tdc = find_type_de_champ_by_stable_id(stable_id, revision)
        tdc ? "{#{tdc.libelle}}" : match
      end
    end

    private

    def find_type_de_champ_by_libelle(libelle, revision)
      revision.types_de_champ.find { |tdc| tdc.libelle&.strip&.casecmp?(libelle.strip) }
    end

    def find_type_de_champ_by_stable_id(stable_id, revision)
      revision.types_de_champ.find { |tdc| tdc.stable_id == stable_id }
    end
  end
end
