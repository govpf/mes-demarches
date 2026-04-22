# frozen_string_literal: true

# pf: Recalcul ciblé des formules temporelles d'un dossier.
#
# Deux familles de dépendances nécessitent des recalculs hors du flow normal
# (le flow normal = cascade sur save d'un champ source) :
#
#   1. **clock_dependent** : formules qui utilisent AUJOURDHUI/MAINTENANT/
#      AGE/EST_PASSEE/EST_FUTURE — leur valeur change avec le temps qui
#      passe. Recalcul quotidien via Cron::RefreshClockDependentFormulasJob,
#      scopé par état (brouillon → public+privé, actif non-brouillon →
#      privé seulement).
#
#   2. **state_dependent** : formules qui référencent les timestamps d'état
#      du dossier ({dossier_depose_at}, {dossier_en_instruction_at}, etc.).
#      Ces valeurs changent à chaque transition. Recalcul synchrone via
#      les hooks after_commit_passer_en_*, sans distinction public/privé
#      (la règle "si une source change, on recalcule" prime).
module DossierFormulaRefreshConcern
  extend ActiveSupport::Concern

  # pf: Timestamps d'état du dossier qui, s'ils changent, peuvent faire
  # bouger la valeur d'une formule state_dependent.
  STATE_TIMESTAMP_COLUMNS = [:depose_at, :en_construction_at, :en_instruction_at, :processed_at].freeze

  included do
    # pf: Hook Rails after_commit (plutôt que AASM after_commit par transition)
    # pour isoler le changement dans ce concern et éviter d'éditer
    # dossier_state_concern à chaque ajout d'un nouveau trigger. Filtré par
    # un changement effectif de timestamp d'état + présence d'au moins une
    # formule state_dependent.
    after_commit :refresh_state_dependent_formulas_if_needed, on: :update
  end

  # pf: Recalcule les formules state_dependent après une transition d'état.
  # Appelée depuis les callbacks after_commit_passer_en_* de Dossier.
  def refresh_state_dependent_formulas
    refresh_formulas_matching(&:state_dependent)
  end

  # pf: Recalcule les formules clock_dependent selon le scope fourni.
  # scope: :all → publiques + privées (pour dossiers en brouillon)
  # scope: :private_only → annotations privées uniquement (pour dossiers
  # actifs déposés, où les formules publiques sont figées)
  def refresh_clock_dependent_formulas(scope: :all)
    refresh_formulas_matching do |tdc|
      next false unless tdc.clock_dependent
      scope == :private_only ? tdc.private? : true
    end
  end

  private

  def refresh_state_dependent_formulas_if_needed
    return unless STATE_TIMESTAMP_COLUMNS.any? { |col| saved_change_to_attribute?(col) }
    return unless has_state_dependent_formula?
    refresh_state_dependent_formulas
  end

  def has_state_dependent_formula?
    revision&.types_de_champ&.any? { |tdc| tdc.formule? && tdc.state_dependent }
  end

  # pf: Boucle générique de recalcul. Utilise update_column pour éviter de
  # déclencher les callbacks (pas de cascade parasite, pas de re-store via
  # store_computed_value). Si un dossier contient une formule qui dépend
  # d'une autre formule recalculée ici, l'ordre de revision garantit la
  # cohérence : les types_de_champ sont ordonnés par position et les
  # formules ne peuvent référencer que des champs qui précèdent.
  def refresh_formulas_matching(&block)
    service = FormulaCalculationService.new(self)
    matching_tdcs = revision.types_de_champ.filter { |tdc| tdc.formule? && yield(tdc) }
    return if matching_tdcs.empty?

    matching_tdcs.each do |tdc|
      formule_champs_for_tdc(tdc).each do |champ|
        new_value = service.compute_value(champ)
        champ.update_column(:value, new_value) if champ.value != new_value
      rescue StandardError => e
        Rails.logger.error("[FormulaRefresh] dossier=#{id} champ=#{champ.id} error=#{e.class}: #{e.message}")
      end
    end
  end

  def formule_champs_for_tdc(tdc)
    # pf: filter sur stable_id seulement — le dossier est lié à une revision
    # donnée, et stable_id est unique dans une revision. Le champ projeté
    # peut ne pas avoir type_de_champ_id (construction lazy via build_champ).
    (project_champs_public_all + project_champs_private_all)
      .filter { |c| c.stable_id == tdc.stable_id }
  end
end
