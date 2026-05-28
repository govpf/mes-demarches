# frozen_string_literal: true

describe TypesDeChamp::FormuleTypeDeChamp do
  let(:type_de_champ) { build(:type_de_champ_formule, formule_expression: expression) }
  let(:formule_type_de_champ) { TypesDeChamp::FormuleTypeDeChamp.new(type_de_champ) }

  describe 'validation' do
    context 'with valid expression' do
      let(:expression) { '1 + 1' }

      it 'is valid' do
        expect(formule_type_de_champ).to be_valid
        expect(type_de_champ).to be_valid
      end
    end

    context 'with simple field reference' do
      let(:expression) { '{Montant HT} * 1.20' }

      it 'is valid' do
        expect(formule_type_de_champ).to be_valid
        expect(type_de_champ).to be_valid
      end
    end

    context 'with text formula' do
      let(:expression) { 'CONCAT({Prénom}, " ", {Nom})' }

      it 'is valid' do
        expect(formule_type_de_champ).to be_valid
        expect(type_de_champ).to be_valid
      end
    end

    context 'with too long expression' do
      let(:expression) { 'A' * 1001 }

      it 'is invalid' do
        expect(type_de_champ).not_to be_valid
        expect(type_de_champ.errors[:formule_expression]).to be_present
      end
    end

    context 'with invalid field reference' do
      let(:expression) { '{}' }

      it 'is invalid' do
        expect(type_de_champ).not_to be_valid
        expect(type_de_champ.errors[:formule_expression]).to be_present
      end
    end

    context 'with blank expression' do
      let(:expression) { '' }

      it 'is valid' do
        expect(formule_type_de_champ).to be_valid
        expect(type_de_champ).to be_valid
      end
    end
  end

  # pf: La détection de cycle est faite STATIQUEMENT à la save du TDC
  # (et plus au runtime). Une formule qui s'auto-référence (directement
  # ou via une chaîne d'autres formules) est refusée dès l'enregistrement
  # avec une erreur :circular_reference.
  describe 'circular reference detection' do
    let(:procedure) {
      create(:procedure, :published, types_de_champ_public: [
        { type: :formule, libelle: 'A' },
        { type: :formule, libelle: 'B' },
        { type: :formule, libelle: 'C' },
      ])
    }
    let(:revision) { procedure.active_revision }
    let(:tdc_a) { revision.types_de_champ_public.find { |t| t.libelle == 'A' } }
    let(:tdc_b) { revision.types_de_champ_public.find { |t| t.libelle == 'B' } }
    let(:tdc_c) { revision.types_de_champ_public.find { |t| t.libelle == 'C' } }

    it 'rejects a formula that references itself directly' do
      tdc_a.formule_expression = "{tdc#{tdc_a.stable_id}} + 1"
      expect(tdc_a).not_to be_valid
      expect(tdc_a.errors[:formule_expression]).to be_present
    end

    it 'rejects a 2-cycle (A → B → A)' do
      tdc_b.update_columns(options: tdc_b.options.merge('formule_expression' => "{tdc#{tdc_a.stable_id}} + 1"))
      tdc_a.formule_expression = "{tdc#{tdc_b.stable_id}} + 1"
      expect(tdc_a).not_to be_valid
      expect(tdc_a.errors[:formule_expression]).to be_present
    end

    it 'rejects a long cycle (A → B → C → A)' do
      tdc_b.update_columns(options: tdc_b.options.merge('formule_expression' => "{tdc#{tdc_c.stable_id}} + 1"))
      tdc_c.update_columns(options: tdc_c.options.merge('formule_expression' => "{tdc#{tdc_a.stable_id}} + 1"))
      tdc_a.formule_expression = "{tdc#{tdc_b.stable_id}} + 1"
      expect(tdc_a).not_to be_valid
      expect(tdc_a.errors[:formule_expression]).to be_present
    end

    it 'accepts a DAG (A → B → C, no cycle, dependencies respect position order)' do
      tdc_a.update_columns(options: tdc_a.options.merge('formule_expression' => '1 + 1'))
      tdc_b.update_columns(options: tdc_b.options.merge('formule_expression' => "{tdc#{tdc_a.stable_id}} + 1"))
      tdc_c.formule_expression = "{tdc#{tdc_b.stable_id}} + 1"
      expect(tdc_c).to be_valid
    end

    it 'accepts a formula referencing a non-formula field' do
      procedure_with_text = create(:procedure, :published, types_de_champ_public: [
        { type: :integer_number, libelle: 'Source' },
        { type: :formule, libelle: 'F' },
      ])
      source_tdc = procedure_with_text.active_revision.types_de_champ_public.first
      formule_tdc = procedure_with_text.active_revision.types_de_champ_public.last
      formule_tdc.formule_expression = "{tdc#{source_tdc.stable_id}} * 2"
      expect(formule_tdc).to be_valid
    end

    it 'accepts a formula referencing system columns (no cycle possible)' do
      tdc_a.formule_expression = "ANNEE({dossier_depose_at})"
      expect(tdc_a).to be_valid
    end
  end

  # pf: Une formule ne peut référencer que des TDC situés AVANT elle dans
  # le formulaire. L'éditeur frontend filtre déjà les variables proposées,
  # mais on verrouille au backend pour résister aux déplacements de TDC
  # qui transformeraient une référence valide en forward reference.
  describe 'forward reference detection' do
    let(:procedure) {
      create(:procedure, :published, types_de_champ_public: [
        { type: :integer_number, libelle: 'Source 1' },
        { type: :formule, libelle: 'Formule milieu' },
        { type: :integer_number, libelle: 'Source 2' },
      ])
    }
    let(:revision) { procedure.active_revision }
    let(:source1_tdc) { revision.types_de_champ_public.find { |t| t.libelle == 'Source 1' } }
    let(:formule_tdc) { revision.types_de_champ_public.find { |t| t.libelle == 'Formule milieu' } }
    let(:source2_tdc) { revision.types_de_champ_public.find { |t| t.libelle == 'Source 2' } }

    it 'accepts a formula referencing a TDC that precedes it' do
      formule_tdc.formule_expression = "{tdc#{source1_tdc.stable_id}} * 2"
      expect(formule_tdc).to be_valid
    end

    it 'rejects a formula referencing a TDC that comes after it' do
      formule_tdc.formule_expression = "{tdc#{source2_tdc.stable_id}} * 2"
      expect(formule_tdc).not_to be_valid
      expect(formule_tdc.errors[:formule_expression]).to be_present
    end

    it 'accepts a formula referencing only system columns' do
      formule_tdc.formule_expression = "ANNEE({dossier_depose_at})"
      expect(formule_tdc).to be_valid
    end

    it 'rejects a formula mixing valid and forward references' do
      formule_tdc.formule_expression = "{tdc#{source1_tdc.stable_id}} + {tdc#{source2_tdc.stable_id}}"
      expect(formule_tdc).not_to be_valid
      expect(formule_tdc.errors[:formule_expression]).to be_present
    end

    # pf: Non-régression — l'éditeur propose les siblings antérieurs d'un même
    # bloc, la validation backend doit accepter cette référence (le bug
    # historique faisait diverger éditeur et validation, les siblings étaient
    # rejetés alors qu'ils étaient proposés).
    context 'formula in repetition referencing a sibling field' do
      let(:procedure) {
        create(:procedure, :published, types_de_champ_public: [
          {
            type: :repetition, libelle: 'Bloc', children: [
              { type: :integer_number, libelle: 'Sibling antérieur' },
              { type: :formule, libelle: 'Formule sibling' },
              { type: :integer_number, libelle: 'Sibling postérieur' },
            ],
          },
        ])
      }
      let(:sibling_before_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Sibling antérieur' } }
      let(:sibling_after_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Sibling postérieur' } }
      let(:formule_in_bloc_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Formule sibling' } }

      it 'accepts a sibling that precedes the formula in the same row' do
        formule_in_bloc_tdc.formule_expression = "{tdc#{sibling_before_tdc.stable_id}} * 2"
        expect(formule_in_bloc_tdc).to be_valid
      end

      it 'rejects a sibling that follows the formula in the same row' do
        formule_in_bloc_tdc.formule_expression = "{tdc#{sibling_after_tdc.stable_id}} * 2"
        expect(formule_in_bloc_tdc).not_to be_valid
        expect(formule_in_bloc_tdc.errors[:formule_expression]).to be_present
      end
    end
  end

  describe '#infer_output_type' do
    context 'with arithmetic expression' do
      let(:expression) { '1 + 2' }

      it 'infers number' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('number')
      end
    end

    context 'with comparison' do
      let(:expression) { '{Montant} > 1000' }

      it 'infers boolean' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('boolean')
      end
    end

    context 'with logical function ET' do
      let(:expression) { 'ET({x} > 5, {x} < 100)' }

      it 'infers boolean' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('boolean')
      end
    end

    context 'with SI returning number' do
      let(:expression) { 'SI({x} > 0, 1, 0)' }

      it 'infers number (type of the true branch)' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('number')
      end
    end

    # pf: Bug — Dentaku type le nœud SI avec :numeric (type passé à add_function)
    # quel que soit le type des branches. Sans inspection des branches, une
    # formule retournant du texte serait stockée comme 'number' et la colonne
    # ferait `.to_f` sur la chaîne → "0.0".
    context 'with SI returning a string' do
      let(:expression) { 'SI({x} > 0, "OK", "KO")' }

      it 'infers string from the branches' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('string')
      end
    end

    context 'with SI returning a boolean' do
      let(:expression) { 'SI({x} > 0, true, false)' }

      it 'infers boolean from the branches' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('boolean')
      end
    end

    context 'with SI returning mixed types' do
      let(:expression) { 'SI({x} > 0, "OK", 0)' }

      it 'falls back to string (most permissive)' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('string')
      end
    end

    context 'with nested SI' do
      let(:expression) { 'SI({x} > 0, SI({y} > 0, "A", "B"), "C")' }

      it 'recursively infers string' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('string')
      end
    end

    context 'with date function AUJOURDHUI' do
      let(:expression) { 'AUJOURDHUI()' }

      it 'infers datetime' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('datetime')
      end
    end

    context 'with text function CONCATENER' do
      let(:expression) { 'CONCATENER("Bon", "jour")' }

      it 'infers string' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('string')
      end
    end

    context 'with blank expression' do
      let(:expression) { '' }

      it 'does not set output type' do
        formule_type_de_champ
        expect(type_de_champ.formule_output_type).to be_nil
      end
    end
  end

  # pf: Le storage d'une formule booléenne est "true"/"false" (cohérent avec
  # yes_no/checkbox). À l'affichage usager (vue dossier), on doit traduire en
  # "Oui"/"Non" comme YesNoTypeDeChamp. Pour les autres types, la valeur est
  # rendue brute par la base.
  describe '#champ_value (display layer)' do
    let(:dossier) { create(:dossier) }
    let(:champ) { Champs::FormuleChamp.new(dossier: dossier) }

    before do
      allow(champ).to receive(:type_de_champ).and_return(type_de_champ)
      type_de_champ.formule_output_type = output_type
    end

    context 'when formule_output_type is boolean' do
      let(:expression) { 'SI({x} > 0, true, false)' }
      let(:output_type) { 'boolean' }

      it 'displays "Oui" for stored "true"' do
        champ.value = 'true'
        expect(formule_type_de_champ.champ_value(champ)).to eq('Oui')
      end

      it 'displays "Non" for stored "false"' do
        champ.value = 'false'
        expect(formule_type_de_champ.champ_value(champ)).to eq('Non')
      end

      it 'displays empty for blank value' do
        champ.value = ''
        expect(formule_type_de_champ.champ_value(champ)).to be_blank
      end
    end

    context 'when formule_output_type is string' do
      let(:expression) { 'SI({x} > 0, "OK", "KO")' }
      let(:output_type) { 'string' }

      it 'displays the raw string value (no transformation)' do
        champ.value = '⚓ À QUAI 🚨'
        expect(formule_type_de_champ.champ_value(champ)).to eq('⚓ À QUAI 🚨')
      end
    end

    context 'when formule_output_type is number' do
      let(:expression) { '{x} * 2' }
      let(:output_type) { 'number' }

      it 'displays the raw number value (no transformation)' do
        champ.value = '42'
        expect(formule_type_de_champ.champ_value(champ)).to eq('42')
      end
    end

    context 'when formule_output_type is date' do
      let(:expression) { '{Date de naissance}' }
      let(:output_type) { 'date' }

      it 'formats ISO date as French human-readable' do
        champ.value = '1989-11-15'
        expect(formule_type_de_champ.champ_value(champ)).to eq('15 novembre 1989')
      end

      it 'falls back to raw value if not parseable' do
        champ.value = 'pas une date'
        expect(formule_type_de_champ.champ_value(champ)).to eq('pas une date')
      end
    end

    context 'when formule_output_type is datetime' do
      let(:expression) { 'MAINTENANT()' }
      let(:output_type) { 'datetime' }

      it 'formats ISO datetime with time' do
        champ.value = '2026-04-24T15:40:00+10:00'
        # I18n.l format default → "24 avril 2026 ..h..."
        expect(formule_type_de_champ.champ_value(champ)).to match(/\d{1,2} \w+ \d{4} \d{2}:\d{2}/)
      end
    end

    # pf: distinction entre formule plantée (nil) et formule retournant ""
    # intentionnellement (ex: SI(cond, "X", "")). La couche stockage les
    # distingue, la vue dossier aussi.
    describe 'distinction nil (formule plantée) vs "" (vide légitime)' do
      let(:expression) { 'STXT({Iban}, 1, 4)' }
      let(:output_type) { 'string' }

      it 'displays "—" marker when value is nil (compute failed)' do
        champ.value = nil
        expect(formule_type_de_champ.champ_value(champ)).to eq('—')
      end

      it 'displays empty when value is "" (legitimate empty result)' do
        champ.value = ''
        expect(formule_type_de_champ.champ_value(champ)).to eq('')
      end

      it 'export returns nil for both nil and "" (no marker in CSV)' do
        champ.value = nil
        expect(formule_type_de_champ.champ_value_for_export(champ)).to be_nil
        champ.value = ''
        expect(formule_type_de_champ.champ_value_for_export(champ)).to be_nil
      end
    end
  end

  describe '#estimated_fill_duration' do
    let(:expression) { '1 + 1' }
    let(:revision) { build(:procedure_revision) }

    it 'returns 0 seconds as formule fields are not fillable' do
      expect(formule_type_de_champ.estimated_fill_duration(revision)).to eq(0.seconds)
    end
  end

  # pf: formule_deps est un Hash structuré stocké dans options['formule_deps']
  # calculé à chaque validation. Il remplace les anciens flags booléens
  # clock_dependent / state_dependent (supprimés à l'étape F). Convention : clés absentes <=> false.
  describe 'formule_deps computation' do
    subject(:deps) do
      type_de_champ.valid?
      type_de_champ.options['formule_deps']
    end

    context 'with a single tdc reference' do
      let(:expression) { '{tdc42}' }

      it 'stores the stable_id in champs, no other keys' do
        expect(deps).to eq('champs' => [42])
      end
    end

    context 'with duplicate tdc references' do
      let(:expression) { '{tdc42} + {tdc78} + {tdc42}' }

      it 'deduplicates and sorts the stable_ids' do
        expect(deps['champs']).to eq([42, 78])
      end
    end

    context 'with a path suffix in the tdc reference' do
      let(:expression) { '{tdc42/nom}' }

      it 'strips the path and stores only the stable_id' do
        expect(deps['champs']).to eq([42])
      end
    end

    context 'with AUJOURDHUI() (clock function)' do
      let(:expression) { 'AUJOURDHUI() + DUREE_JOURS(7)' }

      it 'sets has_clock, no champs' do
        expect(deps['has_clock']).to be(true)
        expect(deps['champs']).to eq([])
      end
    end

    # pf: BUG cible de l'étape D — REGEX matche "AGE(" dans un littéral string,
    # l'AST ne le fait pas. Ce test garantit que la détection via l'AST est
    # correcte et que le regex naïf n'est PAS utilisé pour has_clock.
    context 'with AGE inside a string literal (not a function call)' do
      let(:expression) { 'CONCATENER("AGE(x) literal", {tdc42})' }

      it 'does not set has_clock (AGE inside string does not count)' do
        expect(deps).not_to have_key('has_clock')
      end

      it 'still captures the tdc reference' do
        expect(deps['champs']).to eq([42])
      end
    end

    context 'with a dossier state timestamp reference' do
      let(:expression) { '{dossier_depose_at}' }

      it 'sets has_state' do
        expect(deps['has_state']).to be(true)
        expect(deps['champs']).to eq([])
      end
    end

    context 'with individual identity reference' do
      let(:expression) { '{individual_last_name}' }

      it 'sets has_identite' do
        expect(deps['has_identite']).to be(true)
        expect(deps['champs']).to eq([])
      end
    end

    context 'with entreprise identity reference' do
      let(:expression) { '{entreprise_siret}' }

      it 'sets has_identite' do
        expect(deps['has_identite']).to be(true)
        expect(deps['champs']).to eq([])
      end
    end

    context 'with mixed champ reference, clock function, no state/identite' do
      let(:expression) { 'SI(AGE({tdc42}) > 18, "OK", "KO")' }

      it 'captures champ and clock, but not state or identite' do
        expect(deps['champs']).to eq([42])
        expect(deps['has_clock']).to be(true)
        expect(deps).not_to have_key('has_state')
        expect(deps).not_to have_key('has_identite')
      end
    end

    # pf: non-régression — Dentaku::AST::Negation stocke son opérande dans @node,
    # pas dans :left/:right. Sans le guard :node, -AGE({tdc42}) retournait
    # has_clock=false (enfant ignoré silencieusement).
    context 'with clock function nested under a Negation node' do
      let(:expression) { '-AGE({tdc42}) + 100' }

      it 'detects clock function nested under a Negation node' do
        expect(deps['has_clock']).to be(true)
      end
    end

    context 'with blank expression' do
      let(:expression) { '' }

      it 'stores only the champs key with empty array' do
        expect(deps).to eq('champs' => [])
      end
    end

    # pf: non-régression — formule_deps doit couvrir les cas has_clock et has_state
    # (les anciens flags clock_dependent / state_dependent ont été supprimés à l'étape F).
    context 'non-regression: formule_deps covers clock and state detection' do
      context "AUJOURDHUI() sets has_clock" do
        let(:expression) { 'AUJOURDHUI()' }

        it "sets formule_deps['has_clock'] to true" do
          type_de_champ.valid?
          expect(type_de_champ.formule_deps&.[]('has_clock')).to be(true)
        end
      end

      context "dossier timestamp reference sets has_state" do
        let(:expression) { '{dossier_en_instruction_at}' }

        it "sets formule_deps['has_state'] to true" do
          type_de_champ.valid?
          expect(type_de_champ.formule_deps&.[]('has_state')).to be(true)
        end
      end

      context 'no clock, no state' do
        let(:expression) { '1 + 1' }

        it "does not set formule_deps['has_clock']" do
          type_de_champ.valid?
          expect(type_de_champ.formule_deps).not_to have_key('has_clock')
        end

        it "does not set formule_deps['has_state']" do
          type_de_champ.valid?
          expect(type_de_champ.formule_deps).not_to have_key('has_state')
        end
      end
    end
  end

  # pf: invariant de durabilité — les symboles de CLOCK_FUNCTION_NAMES doivent
  # correspondre à des fonctions effectivement enregistrées dans le calculateur
  # Dentaku. Ce test échouera si une fonction est renommée ou supprimée sans
  # mettre à jour la constante, signalant que le discriminant class.name.is_a?(Symbol)
  # n'est plus fiable pour cette fonction.
  describe 'CLOCK_FUNCTION_NAMES invariant' do
    it 'all clock function names are registered in the Dentaku calculator' do
      calc = FormulaCalculationService.new_calculator
      registry = calc.instance_variable_get(:@function_registry)
      TypesDeChamp::FormuleTypeDeChamp::CLOCK_FUNCTION_NAMES.each do |sym|
        klass = registry.get(sym)
        expect(klass).not_to be_nil, "#{sym} is listed in CLOCK_FUNCTION_NAMES but not registered in the calculator"
        expect(klass.name).to eq(sym), "#{sym} registered class name mismatch: expected #{sym.inspect}, got #{klass.name.inspect}"
      end
    end
  end
end
