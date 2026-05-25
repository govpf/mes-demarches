# frozen_string_literal: true

describe DossierFormulaRefreshConcern do
  let(:procedure) {
    create(:procedure, :published, types_de_champ_private: [
      { type: :formule, libelle: 'Jours en instruction' },
    ])
  }
  let(:revision) { procedure.active_revision }
  let(:dossier) { create(:dossier, :with_populated_champs, :en_construction, procedure: procedure) }
  let(:formule_champ) { dossier.project_champs_private[0] }

  before do
    formule_tdc = revision.types_de_champ.find(&:formule?)
    expr, _ = FormulaExpressionService.convert_to_stable_ids('AUJOURDHUI() - {dossier_en_instruction_at}', revision)
    formule_tdc.update(formule_expression: expr)
    formule_tdc.reload
  end

  describe 'formule_deps on the type_de_champ' do
    it "sets formule_deps['has_clock'] for a clock-dependent formula" do
      formule_tdc = revision.types_de_champ.find(&:formule?)
      expect(formule_tdc.formule_deps&.[]('has_clock')).to be true
    end

    it "sets formule_deps['has_state'] for a state-dependent formula" do
      formule_tdc = revision.types_de_champ.find(&:formule?)
      expect(formule_tdc.formule_deps&.[]('has_state')).to be true
    end
  end

  describe '#refresh_state_dependent_formulas' do
    it 'recomputes a state_dependent private formula' do
      travel_to Time.zone.local(2026, 4, 19, 10, 0, 0) do
        dossier.update_column(:en_instruction_at, Time.zone.local(2026, 4, 10, 10, 0, 0))
        dossier.send(:reset_champs_cache)
        dossier.refresh_state_dependent_formulas
      end
      # AUJOURDHUI() - en_instruction_at (DateTime) → Rational de jours.
      # Timezone PF (UTC-10) vs UTC stockage : la valeur exacte dépend de la
      # conversion. On vérifie juste que le recalcul a bien produit ~9 jours.
      expect(formule_champ.reload.value.to_f).to be_within(1).of(9)
    end
  end

  describe '#refresh_formulas_with_identite_dependents' do
    let(:individual_procedure) {
      create(:procedure, :published, :for_individual, types_de_champ_private: [
        { type: :formule, libelle: 'Formule identite' },
        { type: :formule, libelle: 'Formule horloge' },
      ])
    }
    let(:individual_revision) { individual_procedure.active_revision }
    let(:individual_dossier) {
      create(:dossier, :with_individual, :en_construction, procedure: individual_procedure)
    }

    before do
      identite_tdc = individual_revision.types_de_champ.find { |t| t.formule? && t.libelle == 'Formule identite' }
      clock_tdc    = individual_revision.types_de_champ.find { |t| t.formule? && t.libelle == 'Formule horloge' }

      # formula with has_identite: true
      identite_expr, _ = FormulaExpressionService.convert_to_stable_ids(
        'CONCATENER("Bonjour ", {individual_last_name})',
        individual_revision
      )
      identite_tdc.update!(formule_expression: identite_expr)

      # formula without has_identite (only clock dep)
      clock_expr, _ = FormulaExpressionService.convert_to_stable_ids('AUJOURDHUI()', individual_revision)
      clock_tdc.update!(formule_expression: clock_expr)

      # Materialize initial formula champs
      individual_dossier.compute_formulas_in_order
      individual_dossier.reload
    end

    it 'recomputes formulas with has_identite: true after identity change' do
      individual_dossier.individual.update!(nom: 'Martin')
      individual_dossier.send(:reset_champs_cache)
      individual_dossier.refresh_formulas_with_identite_dependents

      identite_champ = individual_dossier.project_champs_private.find { |c| c.libelle == 'Formule identite' }
      # Individual#nom is stored uppercased — match the actual stored value
      expect(identite_champ.reload.value).to eq('Bonjour MARTIN')
    end

    it 'does NOT recompute formulas without has_identite' do
      # Force the clock formula to a known value first
      clock_champ = individual_dossier.project_champs_private.find { |c| c.libelle == 'Formule horloge' }
      frozen_value = clock_champ.reload.value

      travel_to(2.days.from_now) do
        individual_dossier.individual.update!(nom: 'Durand')
        individual_dossier.send(:reset_champs_cache)
        individual_dossier.refresh_formulas_with_identite_dependents
      end

      # Clock formula should NOT have been updated (no has_identite)
      expect(clock_champ.reload.value).to eq(frozen_value)
    end

    it 'is a no-op when no formula has has_identite' do
      # Build a dossier on a procedure with only a clock formula (no identite refs)
      procedure_no_identite = create(:procedure, :published, :for_individual, types_de_champ_private: [
        { type: :formule, libelle: 'Formule sans identite' },
      ])
      clock_only_tdc = procedure_no_identite.active_revision.types_de_champ.find(&:formule?)
      clock_expr, _ = FormulaExpressionService.convert_to_stable_ids('AUJOURDHUI()', procedure_no_identite.active_revision)
      clock_only_tdc.update!(formule_expression: clock_expr)

      dossier_no_identite = create(:dossier, :with_individual, procedure: procedure_no_identite)
      dossier_no_identite.compute_formulas_in_order

      # Ensure has_identite is NOT set
      expect(clock_only_tdc.reload.formule_deps&.[]('has_identite')).to be_falsey

      expect(dossier_no_identite).not_to receive(:compute_formulas_in_order)
      expect { dossier_no_identite.refresh_formulas_with_identite_dependents }.not_to raise_error
    end
  end

  describe 'after_commit hook triggers refresh on state timestamp change' do
    it 'refreshes when en_instruction_at changes' do
      travel_to Time.zone.local(2026, 4, 19, 10, 0, 0) do
        expect {
          dossier.update!(en_instruction_at: Time.zone.local(2026, 4, 15, 10, 0, 0))
        }.to change { formule_champ.reload.value }
      end
    end

    it 'does NOT refresh when an unrelated column changes' do
      initial_value = formule_champ.reload.value
      dossier.update!(hidden_by_user_at: Time.zone.now)
      expect(formule_champ.reload.value).to eq(initial_value)
    end
  end
end
