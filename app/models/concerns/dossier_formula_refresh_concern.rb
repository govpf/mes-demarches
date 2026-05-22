# frozen_string_literal: true

# pf: Recalcul ciblé des formules temporelles d'un dossier.
#
# Deux familles de dépendances nécessitent des recalculs hors du flow normal
# (le flow normal = cascade sur save d'un champ source) :
#
#   1. **formule_deps['has_clock']** : formules qui utilisent AUJOURDHUI/MAINTENANT/
#      AGE/EST_PASSEE/EST_FUTURE — leur valeur change avec le temps qui
#      passe. Recalcul quotidien via Cron::RefreshClockDependentFormulasJob,
#      scopé par état (brouillon → public+privé, actif non-brouillon →
#      privé seulement).
#
#   2. **formule_deps['has_state']** : formules qui référencent les timestamps d'état
#      du dossier ({dossier_depose_at}, {dossier_en_instruction_at}, etc.).
#      Ces valeurs changent à chaque transition. Recalcul synchrone via
#      les hooks after_commit_passer_en_*, sans distinction public/privé
#      (la règle "si une source change, on recalcule" prime).
module DossierFormulaRefreshConcern
  extend ActiveSupport::Concern

  # pf: Timestamps d'état du dossier qui, s'ils changent, peuvent faire
  # bouger la valeur d'une formule avec formule_deps['has_state'] = true.
  STATE_TIMESTAMP_COLUMNS = [:depose_at, :en_construction_at, :en_instruction_at, :processed_at].freeze

  included do
    # pf: Hook Rails after_commit (plutôt que AASM after_commit par transition)
    # pour isoler le changement dans ce concern et éviter d'éditer
    # dossier_state_concern à chaque ajout d'un nouveau trigger. Filtré par
    # un changement effectif de timestamp d'état + présence d'au moins une
    # formule avec formule_deps['has_state'] = true.
    after_commit :refresh_state_dependent_formulas_if_needed, on: :update
  end

  # pf: Recalcule les formules avec formule_deps['has_state'] = true après une transition d'état.
  # Appelée depuis les callbacks after_commit_passer_en_* de Dossier.
  def refresh_state_dependent_formulas
    refresh_formulas_matching { |tdc| tdc.formule_deps&.[]('has_state') }
  end

  # pf: Recalcule les formules qui référencent l'identité du déclarant
  # (champs {individual_*} ou {entreprise_*}). Appelé explicitement par les
  # controllers après modification de l'identité — pas de callback AR sur
  # Individual/Etablissement pour respecter la convention "cascade explicite"
  # documentée dans CLAUDE.md.
  def refresh_formulas_with_identite_dependents
    matching = revision.types_de_champ.filter do |tdc|
      tdc.formule? && tdc.formule_deps&.[]('has_identite')
    end
    return if matching.empty?

    compute_formulas_in_order(only: matching.map(&:stable_id).to_set)
  end

  # pf: Recalcule les formules avec formule_deps['has_clock'] = true selon le scope fourni.
  # scope: :all → publiques + privées (pour dossiers en brouillon)
  # scope: :private_only → annotations privées uniquement (pour dossiers
  # actifs déposés, où les formules publiques sont figées)
  def refresh_clock_dependent_formulas(scope: :all)
    refresh_formulas_matching do |tdc|
      next false unless tdc.formule_deps&.[]('has_clock')
      scope == :private_only ? tdc.private? : true
    end
  end

  # pf: Recalcule les formules dépendant d'un champ source qui vient d'être
  # modifié. À appeler explicitement par tout site interactif qui modifie un
  # champ source — controller usager (édition d'un champ public), controller
  # instructeur (édition d'une annotation privée), mutations GraphQL,
  # services external_data (SIRET, référentiels qui peuplent value_json/data).
  #
  # Les flux batch (clone, prefill, rebase, merge user_buffer→main) gèrent
  # leur propre recalcul via compute_formulas_in_order et n'appellent PAS
  # cette méthode — éviter une cascade par champ pendant un autosave de
  # collection (cf. bug PG::UniqueViolation sur clone, MES-DEMARCHES-350).
  #
  # Le caller est responsable de décider qu'un changement effectif a eu lieu
  # (sur value, value_json, data, external_id, etablissement_id). Cette
  # méthode ne contrôle plus saved_change_to_value? — couvrir aussi les
  # changements de data permet aux formules de réagir aux retours de webhook
  # SIRET ou aux mises à jour de colonnes référentielles.
  def refresh_formulas_after(champ)
    return unless champ&.stable_id
    # pf: Court-circuit rapide — si la révision n'a aucune formule, rien à faire.
    return unless revision.types_de_champ.any?(&:formule?)
    # pf: Les champs formule eux-mêmes ne déclenchent pas de recalcul (anti-boucle)
    return if champ.type_de_champ.formule?

    # pf: Pré-calcul des stable_ids transitivement dépendants via le graphe
    # pur des types_de_champ (pas d'accès à project_champs).
    dependent_stable_ids = champ.dependent_formula_stable_ids
    # pf: Filtre privacy — les formules privées ne peuvent être écrites que sur
    # main (cf. check_valid_stream_on_write?). Quand la source est sur
    # user:buffer, on skip les formules privées : elles seront recalculées au
    # moment où les changements sont committés vers main (dépôt / instruction).
    if champ.stream != Champ::MAIN_STREAM && dependent_stable_ids.any?
      formula_tdcs_by_sid = revision.types_de_champ.filter(&:formule?).index_by(&:stable_id)
      dependent_stable_ids = dependent_stable_ids.reject { |sid| formula_tdcs_by_sid[sid]&.private? }
    end
    return if dependent_stable_ids.empty?

    # pf: with_champ_stream propage le stream du champ source au dossier le
    # temps de la cascade — tous les upserts de champs formule créés en
    # cascade restent sur le même stream (cohérence avec
    # check_valid_stream_on_write?).
    with_champ_stream(champ) do
      compute_formulas_in_order(
        seed_overrides: { champ.stable_id => champ.value },
        only: dependent_stable_ids,
        # pf: propagation du row_id de la source — limite le recalcul aux
        # Champs formule de la même row (cas répétition) + ceux hors
        # répétition. Évite de recalculer toutes les rows alors que seule
        # celle de la source modifiée a été affectée.
        row_id: champ.row_id
      )
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
  #   row_id         : nil par défaut (= toutes les rows). Si non-nil, limite
  #                    le recalcul aux Champs formule de cette row + ceux hors
  #                    répétition. Utilisé par refresh_formulas_after pour ne
  #                    recalculer que la row de la source modifiée (les autres
  #                    rows ne sont pas affectées par la modif).
  #
  # Retourne : le hash overrides complet { stable_id => value } incluant
  # les valeurs initiales et toutes les formules calculées. Permet à
  # l'appelant d'enchaîner sans réinterroger la BDD.
  def compute_formulas_in_order(seed_overrides: {}, only: nil, persist: true, create_missing: true, row_id: nil, system_write: false)
    formula_tdcs = revision.types_de_champ.filter(&:formule?)
    formula_tdcs = formula_tdcs.filter { |tdc| only.include?(tdc.stable_id) } if only
    return seed_overrides.dup if formula_tdcs.empty?

    overrides = seed_overrides.dup
    # pf: le service lit @value_overrides par référence, donc les nouvelles
    # entrées ajoutées au fil de l'itération sont visibles au calcul suivant.
    service = FormulaCalculationService.new(self, value_overrides: overrides)

    formula_tdcs.each do |tdc|
      formule_champs_for_tdc(tdc, row_id: row_id).each do |formule_champ|
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
              send(:champ_upsert_by!, tdc, formule_champ.row_id, system_write: system_write)
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
  # Pour les formules dépendant d'un champ que l'usager modifie, c'est l'appel
  # explicite à refresh_formulas_after (par les controllers / mutations /
  # services) qui prend le relais.
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
    revision&.types_de_champ&.any? { |tdc| tdc.formule? && tdc.formule_deps&.[]('has_state') }
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

  def formule_champs_for_tdc(tdc, row_id: nil)
    # pf: lookup direct sur la collection (Champs persistés ou in-memory du
    # stream courant). Évite project_champs_*_all qui matérialiserait tous les
    # TDC de la révision pour chaque appel — coût O(N TDC) × O(N formules)
    # par cascade, alors qu'on n'a besoin que des Champs du tdc en cours.
    #
    # Filtre row_id : si row_id est passé (cascade depuis un Champ source
    # dans une row), on garde les Champs de la même row + les Champs hors
    # répétition (row_id=nil). Sans row_id (recalcul global, ex: rebase /
    # merge / refresh_clock), on traite toutes les rows.
    champs_for_tdc = champs.filter do |c|
      c.stable_id == tdc.stable_id && c.stream == stream &&
        (row_id.nil? || c.row_id == row_id || c.row_id.nil?)
    end
    return champs_for_tdc if champs_for_tdc.any?

    # pf: aucun Champ persisté pour ce TDC. Pour permettre à
    # compute_formulas_in_order de matérialiser le Champ via champ_upsert_by!
    # (cas rebase d'une formule ajoutée à la révision, ou tout flow où le TDC
    # formule existe sans son Champ), on retourne un Champ in-memory.
    #
    # Skip pour les TDC enfants d'une répétition : leur INSERT requiert un
    # row_id (cf. check_valid_row_id_on_write?) qu'on n'a pas systématiquement
    # ici. Conséquence : un rebase qui ajoute une formule en répétition ne
    # crée pas les Champs formule pour les rows existantes — la formule reste
    # vide jusqu'à la prochaine modif d'une source dans chaque row.
    # TODO: gérer ce cas en itérant les rows existantes du parent répétition
    # et en buildant un Champ formule par row.
    return [] if tdc.child?(revision)

    # Le build est forcément avec row_id=nil : on est par construction sur un
    # TDC hors répétition (le return [] au-dessus filtre les enfants), et
    # check_valid_row_id_on_write? exige row_id=nil pour les TDC hors répétition.
    [tdc.build_champ(dossier: self, row_id: nil, stream: stream)]
  end
end
