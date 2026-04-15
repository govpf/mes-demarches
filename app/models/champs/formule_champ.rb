# frozen_string_literal: true

class Champs::FormuleChamp < Champ
  before_validation :store_computed_value

  validates :value, presence: true, if: :validate_champ_value?

  # value : on utilise le reader AR par défaut (read_attribute).
  # Le calcul est fait UNE SEULE FOIS via before_validation :store_computed_value
  # ou via refresh_dependent_formulas (after_save sur le champ source).
  # On ne surcharge PAS value — sinon chaque appel (validation, export, API,
  # Turbo render) recrée un FormulaCalculationService + index colonnes.

  def blank?
    value.blank? && type_de_champ.formule_expression.blank?
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
    # pf: garde contre les champs formule orphelins — un Champ persisté dont
    # le TDC a été supprimé de la révision (cas typique d'un dossier de preview
    # après une suppression de champ formule via l'éditeur admin). Sans cette
    # garde, type_de_champ lève un RuntimeError qui fait crasher la page de
    # preview. Les champs non persistés (construits en mémoire par build_champ)
    # sont laissés passer : leur TDC est par construction valide.
    return if persisted? && !in_dossier_revision?

    if type_de_champ.formule_expression.present?
      write_attribute(:value, compute_value_from_formula)
    end
  end
end
