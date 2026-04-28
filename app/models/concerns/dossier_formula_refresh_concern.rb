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

  # pf: Méthode unique de recalcul des formules d'un dossier dans l'ordre
  # topologique. Utilise l'invariant "position TDC = ordre topologique" (cf.
  # TypesDeChamp::FormuleTypeDeChamp#forward_reference?) : itérer les TDC
  # formule dans l'ordre des positions garantit qu'au moment où on calcule
  # une formule, toutes ses sources et formules amont sont déjà résolues.
  #
  # Les valeurs calculées sont accumulées dans `value_overrides` et lues par
  # le service au calcul suivant — pas de relecture BDD par formule.
  #
  # Paramètres :
  #   seed_overrides : Hash { stable_id => value } valeurs initiales. Typique :
  #                    la nouvelle valeur d'un champ source qui vient d'être
  #                    sauvegardée et qui a déclenché une cascade.
  #   only           : nil (toutes les formules de la révision) ou Set/Array de
  #                    stable_ids à recalculer (cascade ciblée).
  #   persist        : true par défaut. Si false, retourne les valeurs sans
  #                    toucher la BDD (mode "calcul pur" pour preview).
  #   create_missing : true par défaut. Si false, on ne matérialise pas les
  #                    champs formule absents en BDD — pertinent pour le calcul
  #                    initial qui ne doit pas créer de champs si la création
  #                    du dossier ne les a pas faits (sinon doublons avec les
  #                    flux qui créent les champs après le dossier, comme
  #                    certaines factories de tests).
  #
  # Retourne : le hash overrides complet { stable_id => value } incluant
  # les valeurs initiales et toutes les formules calculées. Permet à
  # l'appelant d'enchaîner sans réinterroger la BDD.
  def compute_formulas_in_order(seed_overrides: {}, only: nil, persist: true, create_missing: true)
    formula_tdcs = revision.types_de_champ.filter(&:formule?)
    formula_tdcs = formula_tdcs.filter { |tdc| only.include?(tdc.stable_id) } if only
    return seed_overrides.dup if formula_tdcs.empty?

    overrides = seed_overrides.dup
    # pf: le service lit @value_overrides par référence, donc les nouvelles
    # entrées ajoutées au fil de l'itération sont visibles au calcul suivant.
    service = FormulaCalculationService.new(self, value_overrides: overrides)

    formula_tdcs.each do |tdc|
      formule_champs_for_tdc(tdc).each do |formule_champ|
        new_value = service.compute_value(formule_champ)
        overrides[tdc.stable_id] = new_value
        next unless persist

        if formule_champ.persisted?
          # pf: champ formule déjà en BDD — update direct, pas de cascade.
          # update_columns met à jour value ET updated_at (cohérence pour les
          # consommateurs basés sur updated_at, et pré-requis pour un futur
          # cache "tdc.updated_at > champ.updated_at" en draft preview).
          if formule_champ.read_attribute(:value) != new_value
            formule_champ.update_columns(value: new_value, updated_at: Time.zone.now)
          end
        else
          # pf: champ non persisté — création seulement si create_missing.
          # Cas typique de création : rebase qui ajoute un nouveau TDC formule.
          # Cas typique de skip : compute_initial_formulas qui tourne au
          # after_commit du dossier mais n'a pas vocation à insérer des champs.
          next unless create_missing
          target = Dossier.no_touching do
            with_champ_stream(formule_champ) do
              send(:champ_upsert_by!, tdc, formule_champ.row_id)
            end
          end
          if target.read_attribute(:value) != new_value
            target.update_columns(value: new_value, updated_at: Time.zone.now)
          end
        end
      end
    end

    overrides
  end

  # pf: Calcul initial des formules d'un dossier — appel explicite depuis
  # les controllers / services qui créent un dossier. Pattern "option 3" :
  # pas de hook after_commit (qui pose problème avec les factories de tests
  # qui ajoutent des champs après la création) ; au contraire, l'appelant
  # contrôle explicitement le moment où on calcule, juste après build_default_values
  # + save! (ou après prefill! pour les flux de préfill).
  #
  # Couvre :
  # - formules constantes ({1 + 1}) / sur fonctions système (AUJOURDHUI())
  # - formules sur champs source préremplis (cas Commencer)
  #
  # Pour les formules dépendant d'un champ que l'usager modifie, c'est la
  # cascade refresh_dependent_formulas qui prend le relais.
  def compute_initial_formulas
    return unless revision&.types_de_champ&.any?(&:formule?)
    compute_formulas_in_order
  rescue StandardError => e
    Rails.logger.error("[InitialFormulas] dossier=#{id} error=#{e.class}: #{e.message}")
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
