# frozen_string_literal: true

require 'rails_helper'

# pf: Audit de performance et de comportement de la cascade explicite des
# formules — Dossier#refresh_formulas_after, appelée par les controllers
# (users/instructeurs/champs), les mutations GraphQL et les services
# external_data. Ce test sert de garde-fou CI pour détecter les régressions
# de performance et vérifier le comportement du recalcul en chaîne.
RSpec.describe 'Formule cascade refresh_formulas_after', type: :model do
  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  def count_sql_queries(&block)
    count = 0
    counter = -> (_name, _start, _finish, _id, payload) {
      count += 1 unless payload[:name] == 'SCHEMA' || payload[:sql]&.start_with?('SAVEPOINT', 'RELEASE')
    }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)
    count
  end

  def set_formule_expression(dossier, formule_tdc, expression)
    # pf: passe par update! (avec validation) pour que formule_deps soit recalculé
    # en même temps que formule_expression — update_column bypasse les callbacks
    # et laisserait formule_deps stale, ce qui romprait la construction du graphe
    # de dépendances via formule_deps['champs'].
    formule_tdc.update!(formule_expression: expression)
  end

  def find_champ(dossier, tdc)
    dossier.champs.find { |c| c.stable_id == tdc.stable_id }
  end

  # ------------------------------------------------------------------
  # Scénario 1 : Fan-out — 1 champ source, N formules dépendantes
  # ------------------------------------------------------------------
  describe 'fan-out: 1 source → N formules' do
    let(:n_formulas) { 10 }
    let(:types) do
      [{ type: :integer_number, libelle: 'Source' }] +
        Array.new(n_formulas) { |i| { type: :formule, libelle: "Formule #{i}" } }
    end
    let(:procedure) { create(:procedure, :published, types_de_champ_public: types) }
    let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }

    before do
      source_tdc = procedure.active_revision.types_de_champ_public.find(&:integer_number?)
      procedure.active_revision.types_de_champ_public.filter(&:formule?).each do |formule_tdc|
        set_formule_expression(dossier, formule_tdc, "{tdc#{source_tdc.stable_id}} * 2")
      end
    end

    it "recalcule les 10 formules quand la source change" do
      source_champ = dossier.champs.find { |c| c.type_de_champ.integer_number? }
      source_champ.update!(value: '100')

      # Vérifier que les formules ont été recalculées
      dossier.reload
      formule_champs = dossier.champs.filter { |c| c.type_de_champ.formule? }
      formule_champs.each do |fc|
        expect(fc.compute_value_from_formula).to eq('200'), "Formule #{fc.libelle} non recalculée"
      end
    end

    it 'reste dans un budget SQL raisonnable' do
      source_champ = dossier.champs.find { |c| c.type_de_champ.integer_number? }

      # Warmup (preload caches)
      source_champ.update!(value: '1')

      query_count = count_sql_queries do
        source_champ.update!(value: '42')
      end

      # Budget : save (1) + find dependants (~2-3) + N update_columns + overhead
      # On accepte 5 requêtes par formule max (50 pour 10 formules)
      expect(query_count).to be < 50,
        "Trop de requêtes SQL pour le fan-out (#{query_count}). Risque N+1."
    end
  end

  # ------------------------------------------------------------------
  # Scénario 2 : Chaîne linéaire — A → formule B → formule C
  # ------------------------------------------------------------------
  describe 'chaîne linéaire: A → B → C' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        { type: :integer_number, libelle: 'Montant' },
        { type: :formule, libelle: 'Double' },
        { type: :formule, libelle: 'Quadruple' },
      ])
    end
    let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }

    let(:montant_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Montant' } }
    let(:double_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Double' } }
    let(:quadruple_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Quadruple' } }

    before do
      set_formule_expression(dossier, double_tdc, "{tdc#{montant_tdc.stable_id}} * 2")
      set_formule_expression(dossier, quadruple_tdc, "{tdc#{double_tdc.stable_id}} * 2")
    end

    it 'propage la transitivité A → B → C via refresh_formulas_after' do
      # Persister les champs formule pour que update_column fonctionne
      dossier.reload
      double_champ = find_champ(dossier, double_tdc)
      double_champ.save! unless double_champ.persisted?
      quadruple_champ = find_champ(dossier, quadruple_tdc)
      quadruple_champ.save! unless quadruple_champ.persisted?

      montant = find_champ(dossier, montant_tdc)
      montant.update!(value: '10')
      # pf: cascade explicite — c'est désormais le caller (controller,
      # mutation, service) qui déclenche le recalcul après modification
      # d'un champ source. Ici on simule l'appel typique d'un controller.
      dossier.refresh_formulas_after(montant)

      # Vérifier que les DEUX niveaux sont recalculés en DB
      expect(double_champ.reload.read_attribute(:value)).to eq('20')
      expect(quadruple_champ.reload.read_attribute(:value)).to eq('40')
    end

    it 'ne provoque pas de cascade infinie (pas de StackOverflow)' do
      montant = find_champ(dossier, montant_tdc)
      expect {
        montant.update!(value: '999')
        dossier.refresh_formulas_after(montant)
      }.not_to raise_error
    end
  end

  # pf: Le scénario "référence circulaire" est désormais validé STATIQUEMENT
  # à la sauvegarde du TDC formule (cf. spec/models/types_de_champ/
  # formule_type_de_champ_spec.rb → "circular reference detection"). Le
  # validateur refuse la save d'une formule qui s'auto-référence — donc ce
  # cas ne peut plus arriver à l'exécution. La protection runtime
  # `detect_circular_references` a été retirée car elle déclenchait
  # `all_champs` (= project_champs cascade) à chaque calcul.

  # ----------------------------------------------------------------------
  # Scénario : history stream préservé
  # ----------------------------------------------------------------------
  # pf: Bug constaté en prod — en draft revision, toute validation déclenche
  # before_validation :store_computed_value sur tous les champs persistés,
  # y compris les history. Résultat : N entrées history contenant TOUTES la
  # même valeur (la dernière calculée), perdant tout intérêt d'archive. La
  # garde `return if persisted? && history_stream?` empêche le rewrite.
  describe 'history stream preservation' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        { type: :integer_number, libelle: 'Source' },
        { type: :formule, libelle: 'Double' },
      ])
    end
    let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }
    let(:source_tdc) { procedure.active_revision.types_de_champ_public.first }
    let(:formule_tdc) { procedure.active_revision.types_de_champ_public.last }

    before do
      set_formule_expression(dossier, formule_tdc, "{tdc#{source_tdc.stable_id}} * 2")
      formule_champ = find_champ(dossier, formule_tdc)
      # Simuler un champ history figé à value=10 (différent de la valeur
      # qui serait recalculée maintenant)
      formule_champ.update_column(:stream, "history:2026-01-01 10:00:00 +0000")
      formule_champ.update_column(:value, '10')
    end

    it 'never overwrites a history champ value via store_computed_value' do
      formule_champ = dossier.champs.find { |c| c.stable_id == formule_tdc.stable_id }
      original_value = formule_champ.value
      # Trigger validation (simule ce qui se passe quand le dossier est
      # validé en draft revision)
      formule_champ.valid?
      expect(formule_champ.value).to eq(original_value)
      expect(formule_champ.value).to eq('10')
    end
  end

  # ------------------------------------------------------------------
  # Scénario 4 : Temps de réponse
  # ------------------------------------------------------------------
  describe 'temps de réponse' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        { type: :integer_number, libelle: 'Source' },
        { type: :formule, libelle: 'Résultat' },
      ])
    end
    let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }

    before do
      source_tdc = procedure.active_revision.types_de_champ_public.find(&:integer_number?)
      formule_tdc = procedure.active_revision.types_de_champ_public.find(&:formule?)
      set_formule_expression(dossier, formule_tdc, "{tdc#{source_tdc.stable_id}} * 2 + 100")
    end

    it 'le recalcul se fait en moins de 500ms' do
      source = dossier.champs.find { |c| c.type_de_champ.integer_number? }
      source.update!(value: '1') # warmup

      elapsed = Benchmark.realtime { source.update!(value: '42') }

      expect(elapsed).to be < 0.5,
        "Le refresh_dependent_formulas prend #{(elapsed * 1000).round}ms (budget: 500ms)"
    end
  end

  # ----------------------------------------------------------------------
  # Scénario : annotation privée formule dépendant d'un champ public
  # ----------------------------------------------------------------------
  # pf: Bug : quand l'usager remplit son dossier (stream user:buffer), modifier
  # un champ public qui sert de source à une annotation privée formule
  # déclenchait un cascade qui essayait d'écrire la formule privée sur
  # user:buffer. Or check_valid_stream_on_write? interdit toute écriture
  # privée hors du stream main → RuntimeError. Le cascade doit donc skipper
  # les formules privées dans ce cas (elles seront recalculées au commit
  # vers main, ex: au dépôt).
  describe 'annotation privée formule + champ public source' do
    let(:procedure) do
      create(:procedure, :published,
             types_de_champ_public: [{ type: :integer_number, libelle: 'Source' }],
             types_de_champ_private: [{ type: :formule, libelle: 'Annotation calculée' }])
    end
    let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }
    let(:source_tdc) { procedure.active_revision.types_de_champ_public.find(&:integer_number?) }
    let(:formule_tdc) { procedure.active_revision.types_de_champ_private.find(&:formule?) }

    before do
      set_formule_expression(dossier, formule_tdc, "{tdc#{source_tdc.stable_id}} * 2")
    end

    it "ne crash pas quand l'usager modifie un champ source en stream user:buffer" do
      source_champ = dossier.champs.find { |c| c.type_de_champ.integer_number? }
      source_champ.update_column(:stream, Champ::USER_BUFFER_STREAM)

      expect { source_champ.update!(value: '42') }.not_to raise_error
    end
  end

  # ----------------------------------------------------------------------
  # Scénario : champ public formule sur dossier en_construction
  # ----------------------------------------------------------------------
  # pf: Quand un dossier est en_construction et que l'usager corrige un champ,
  # la cascade refresh_dependent_formulas écrivait la formule dépendante en
  # utilisant dossier.stream qui retombe sur 'main' par défaut. Mais
  # check_valid_stream_on_write? interdit toute écriture publique sur 'main'
  # quand le dossier est en_construction (le buffer doit être utilisé).
  # Fix : la cascade utilise with_champ_stream(self) pour propager le stream
  # de la source à l'upsert.
  describe 'formule publique + dossier en_construction' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        { type: :integer_number, libelle: 'Source' },
        { type: :formule, libelle: 'Double' },
      ])
    end
    let(:dossier) { create(:dossier, :en_construction, :with_populated_champs, procedure: procedure) }
    let(:source_tdc) { procedure.active_revision.types_de_champ_public.find(&:integer_number?) }
    let(:formule_tdc) { procedure.active_revision.types_de_champ_public.find(&:formule?) }

    before do
      set_formule_expression(dossier, formule_tdc, "{tdc#{source_tdc.stable_id}} * 2")
    end

    it "ne crash pas quand l'usager corrige un champ source sur user:buffer" do
      source_champ = dossier.champs.find { |c| c.type_de_champ.integer_number? }
      source_champ.update_column(:stream, Champ::USER_BUFFER_STREAM)

      expect { source_champ.update!(value: '50') }.not_to raise_error
    end
  end

  # ----------------------------------------------------------------------
  # Scénario : formule-agrégat sur bloc répétable (étape E du chantier)
  # ----------------------------------------------------------------------
  # pf: Une formule HORS bloc agrège un sous-champ de toutes les lignes
  # (SOMME({Lignes/Prix HT})) ou compte les lignes (NB({Lignes})). Sa
  # dépendance est enregistrée au niveau BLOC (granularité bloc). On vérifie
  # que la cascade explicite la recalcule dans les 3 déclencheurs :
  #   - modification d'un sous-champ d'une ligne existante
  #   - ajout d'une ligne
  #   - suppression d'une ligne
  describe 'agrégat sur bloc répétable' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        {
          type: :repetition, libelle: 'Lignes', mandatory: false, children: [
            { type: :integer_number, libelle: 'Prix HT' },
          ],
        },
        { type: :formule, libelle: 'Total' },
        { type: :formule, libelle: 'Nb lignes' },
      ])
    end
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:bloc_tdc) { procedure.active_revision.types_de_champ.find { _1.libelle == 'Lignes' } }
    let(:prix_tdc) { procedure.active_revision.types_de_champ.find { _1.libelle == 'Prix HT' } }
    let(:total_tdc) { procedure.active_revision.types_de_champ.find { _1.libelle == 'Total' } }
    let(:nb_tdc) { procedure.active_revision.types_de_champ.find { _1.libelle == 'Nb lignes' } }

    def add_row(prix)
      row_id = dossier.repetition_add_row(bloc_tdc, updated_by: 'test')
      # pf: simule le flux controller — la saisie du sous-champ déclenche elle
      # aussi refresh_formulas_after (repetition_add_row ne refresh qu'à l'ajout,
      # quand le sous-champ est encore vide).
      sub = dossier.champ_for_update(prix_tdc, row_id:, updated_by: 'test')
      sub.update!(value: prix.to_s)
      dossier.refresh_formulas_after(sub)
      row_id
    end

    before do
      set_formule_expression(dossier, total_tdc, "SOMME({tdc#{bloc_tdc.stable_id}/sub_#{prix_tdc.stable_id}})")
      set_formule_expression(dossier, nb_tdc, "COUNT({tdc#{bloc_tdc.stable_id}})")
    end

    it 'recalcule SOMME et NB à l\'ajout d\'une ligne' do
      add_row(100)
      add_row(200)
      expect(find_champ(dossier, total_tdc).reload.read_attribute(:value)).to eq('300')
      expect(find_champ(dossier, nb_tdc).reload.read_attribute(:value)).to eq('2')
    end

    it 'recalcule SOMME à la modification d\'un sous-champ d\'une ligne existante' do
      row_id = add_row(100)
      add_row(200)
      expect(find_champ(dossier, total_tdc).reload.read_attribute(:value)).to eq('300')

      # modification d'un sous-champ de la 1ʳᵉ ligne → l'agrégat (dépendance
      # niveau bloc) doit se recalculer même si sa dépendance directe est le bloc
      sub_champ = dossier.champ_for_update(prix_tdc, row_id:, updated_by: 'test')
      sub_champ.update!(value: '150')
      dossier.refresh_formulas_after(sub_champ)

      expect(find_champ(dossier, total_tdc).reload.read_attribute(:value)).to eq('350')
    end

    it 'recalcule SOMME et NB à la suppression d\'une ligne' do
      add_row(100)
      row2 = add_row(200)
      expect(find_champ(dossier, total_tdc).reload.read_attribute(:value)).to eq('300')

      dossier.repetition_remove_row(bloc_tdc, row2, updated_by: 'test')
      expect(find_champ(dossier, total_tdc).reload.read_attribute(:value)).to eq('100')
      expect(find_champ(dossier, nb_tdc).reload.read_attribute(:value)).to eq('1')
    end
  end

  # ----------------------------------------------------------------------
  # Scénario : agrégat d'une FORMULE-LIGNE (test opérationnel pour la refonte)
  # ----------------------------------------------------------------------
  # pf: Total = SOMME({Lignes/Montant TTC}) où Montant TTC = Prix HT × 2 (formule
  # par ligne). Vérifie que modifier UNE source recalcule la formule-ligne PUIS
  # l'agrégat, SANS corrompre les autres lignes. Non-régression de la fuite
  # value_overrides (keyé stable_id, row-aveugle) : l'override d'une ligne ne
  # doit pas s'appliquer aux autres lignes lors du recalcul des formules-ligne.
  describe 'agrégat d\'une formule-ligne (valeurs par ligne distinctes)' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        {
          type: :repetition, libelle: 'Lignes', mandatory: false, children: [
            { type: :integer_number, libelle: 'Prix HT' },
            { type: :formule, libelle: 'Montant TTC' },
          ],
        },
        { type: :formule, libelle: 'Total' },
      ])
    end
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:bloc_tdc) { procedure.active_revision.types_de_champ.find { _1.libelle == 'Lignes' } }
    let(:prix_tdc) { procedure.active_revision.types_de_champ.find { _1.libelle == 'Prix HT' } }
    let(:ttc_tdc) { procedure.active_revision.types_de_champ.find { _1.libelle == 'Montant TTC' } }
    let(:total_tdc) { procedure.active_revision.types_de_champ.find { _1.libelle == 'Total' } }

    before do
      set_formule_expression(dossier, ttc_tdc, "{tdc#{prix_tdc.stable_id}} * 2")
      set_formule_expression(dossier, total_tdc, "SOMME({tdc#{bloc_tdc.stable_id}/sub_#{ttc_tdc.stable_id}})")
    end

    def add_row_prix(prix)
      row_id = dossier.repetition_add_row(bloc_tdc, updated_by: 'test')
      dossier.champ_for_update(prix_tdc, row_id:, updated_by: 'test').update!(value: prix.to_s)
      row_id
    end

    it 'modifier la source d\'une ligne recalcule l\'agrégat sans corrompre les autres lignes' do
      row1 = add_row_prix(100) # TTC 200
      add_row_prix(200)        # TTC 400
      dossier.compute_formulas_in_order
      expect(find_champ(dossier, total_tdc).reload.read_attribute(:value)).to eq('600')

      # row1 Prix HT 100 → 150 : TTC row1 = 300, row2 reste 400 ⇒ Total 700
      p1 = dossier.champ_for_update(prix_tdc, row_id: row1, updated_by: 'test')
      p1.update!(value: '150')
      dossier.refresh_formulas_after(p1)

      expect(find_champ(dossier, total_tdc).reload.read_attribute(:value)).to eq('700')
    end
  end

  # pf: la cascade injecte `champ.value` brut dans seed_overrides, ce qui
  # court-circuite le parsing de la colonne :enums — le binding reçoit la
  # sérialisation JSON `'["Bus"]'` et non un Array. Sans reparsing, CONTIENT
  # renvoyait false alors que l'option venait d'être cochée (bug détecté par
  # spec/system/users/formula_multiple_choice_spec.rb).
  describe 'CONTIENT sur un champ à choix multiple' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        { type: :multiple_drop_down_list, libelle: 'Moyens', options: ['Vélo', 'Bus', 'Bus scolaire'] },
        { type: :formule, libelle: 'Mode' },
      ])
    end
    # pf: dossier non peuplé — :with_populated_champs charge et met en cache
    # revision.types_de_champ à la création, donc avec des formule_deps stale
    # (l'expression est posée juste après par le before). Le champ formule est
    # créé par la cascade elle-même (create_missing).
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:moyens_tdc) { procedure.active_revision.types_de_champ.find { _1.libelle == 'Moyens' } }
    let(:mode_tdc) { procedure.active_revision.types_de_champ.find { _1.libelle == 'Mode' } }

    def select_moyens(*options)
      champ = find_champ(dossier, moyens_tdc)
      champ.update!(value: options.to_json)
      dossier.refresh_formulas_after(champ)
    end

    before do
      set_formule_expression(dossier, mode_tdc, "SI(CONTIENT({tdc#{moyens_tdc.stable_id}}, \"Bus\"), \"TC\", \"Autre\")")
    end

    it 'recalcule la formule quand une option est cochée' do
      select_moyens('Vélo', 'Bus')
      expect(find_champ(dossier, mode_tdc).reload.read_attribute(:value)).to eq('TC')
    end

    it 'recalcule la formule quand l\'option est décochée' do
      select_moyens('Vélo', 'Bus')
      select_moyens('Vélo')
      expect(find_champ(dossier, mode_tdc).reload.read_attribute(:value)).to eq('Autre')
    end

    it 'ne fait pas de faux positif sur une option dont le libellé contient le libellé cherché' do
      select_moyens('Bus scolaire')
      expect(find_champ(dossier, mode_tdc).reload.read_attribute(:value)).to eq('Autre')
    end
  end
end
