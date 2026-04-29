# frozen_string_literal: true

class Champs::FormuleChamp < Champ
  # pf: PAS de validates :value, presence — l'usager ne contrôle pas la
  # valeur d'une formule, donc bloquer le dépôt parce qu'une formule n'a
  # pas pu se calculer (source vide, etc.) est punitif. Le calcul peut
  # être nil (Dentaku silent fail) ou "" (résultat légitime), les deux
  # passent.
  #
  # Calcul de la value : trois chemins, jamais déclenchés par la validation.
  #   1. Création du dossier : appel explicite à dossier.compute_initial_formulas
  #      depuis les controllers (Users::Dossiers#new_dossier, Commencer,
  #      Api::Public::V1, ProcedureRevision#dossier_for_preview).
  #   2. Modification d'un champ source : Champ#after_save :refresh_dependent_formulas
  #      → cascade via compute_formulas_in_order avec seed.
  #   3. Affichage en révision draft (preview admin) :
  #      Dossier#project_champ → recompute en mémoire pour refléter les
  #      modifications d'expression non encore propagées aux dossiers.
  #
  # compute_value_from_formula reste exposé car project_champ s'en sert
  # pour le cas (3). Tous les autres flows passent par compute_formulas_in_order.

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
end
