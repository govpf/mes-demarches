# frozen_string_literal: true

describe DossierFormulaRefreshConcern do
  let(:procedure) {
    create(:procedure, :published, types_de_champ_private: [
      { type: :formule, libelle: 'Jours en instruction' }
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

  describe 'flags on the type_de_champ' do
    it 'marks the formula as clock_dependent' do
      formule_tdc = revision.types_de_champ.find(&:formule?)
      expect(formule_tdc.clock_dependent).to be true
    end

    it 'marks the formula as state_dependent' do
      formule_tdc = revision.types_de_champ.find(&:formule?)
      expect(formule_tdc.state_dependent).to be true
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
