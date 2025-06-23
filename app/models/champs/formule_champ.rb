# frozen_string_literal: true

class Champs::FormuleChamp < Champ
  before_validation :store_computed_value

  validates :value, presence: true, if: :validate_champ_value_or_prefill?

  def blank?
    value.blank?
  end

  def value
    return '' if type_de_champ.formule_expression.blank?
    compute_value_from_formula
  end

  def for_export(path = :value)
    value
  end

  def for_api
    value
  end

  def for_api_v2
    value
  end

  def search_terms
    [value].compact
  end

  def to_s
    value.to_s
  end

  def compute_value_from_formula
    return '' if type_de_champ.formule_expression.blank?

    begin
      calculation_service = FormulaCalculationService.new(dossier)
      calculation_service.compute_value(self)
    rescue StandardError => e
      "Erreur : #{e.message}"
    end
  end

  private

  def store_computed_value
    if type_de_champ.formule_expression.present?
      write_attribute(:value, compute_value_from_formula)
    end
  end
end
