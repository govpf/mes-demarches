# frozen_string_literal: true

describe RefreshClockDependentFormulasDossierJob do
  let(:procedure) {
    create(:procedure, :published, types_de_champ_public: [
      { type: :date, libelle: 'Date de naissance' },
      { type: :formule, libelle: 'Age' },
    ])
  }
  let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }
  # pf: utilise dossier.revision (pas procedure.active_revision) : les deux sont
  # deux instances Ruby distinctes de la même ligne DB, chacune mémoïsant sa
  # propre liste types_de_champ. Si on update le TDC via procedure.active_revision,
  # refresh_formulas_after (qui lit dossier.revision.types_de_champ) voit
  # l'ancienne expression et le recalcul n'a pas lieu.
  let(:revision) { dossier.revision }
  let(:date_champ) { dossier.project_champs_public[0] }
  let(:formule_champ) { dossier.project_champs_public[1] }

  before do
    # pf: tout le setup dans travel_to pour stubber Date.current pendant
    # la cascade de recalcul qui appelle AGE.
    travel_to Time.zone.local(2026, 4, 19) do
      formule_tdc = revision.types_de_champ.find(&:formule?)
      expr, _ = FormulaExpressionService.convert_to_stable_ids('AGE({Date de naissance})', revision)
      formule_tdc.update!(formule_expression: expr)
      date_champ.update!(value: '2000-05-15')
      dossier.send(:reset_champs_cache)
      # pf: depuis la phase 4 (option 3), le calcul initial passe par
      # compute_initial_formulas (avant : déclenché par before_validation lors
      # du save du champ). Update_columns la value en BDD pour que le test
      # lise '25' avant le travel_to du test principal.
      dossier.compute_initial_formulas
      fresh_formule = dossier.project_champs_public[1]
      expect(fresh_formule.reload.value).to eq('25')
    end
  end

  describe '#perform' do
    it 'recalculates AGE after an anniversary has passed' do
      travel_to Time.zone.local(2026, 5, 16) do
        described_class.new.perform(dossier.id, 'all')
      end
      expect(formule_champ.reload.value).to eq('26')
    end

    it 'does nothing when dossier has moved to terminal state' do
      dossier.update_column(:state, 'accepte')
      travel_to Time.zone.local(2026, 5, 16) do
        described_class.new.perform(dossier.id, 'all')
      end
      # Value unchanged (no refresh on terminal)
      expect(formule_champ.reload.value).to eq('25')
    end

    it 'downgrades scope to :private_only if dossier moved from brouillon' do
      # Enqueued as 'all' (dossier was brouillon), but has moved to en_construction
      dossier.update_column(:state, 'en_construction')
      travel_to Time.zone.local(2026, 5, 16) do
        described_class.new.perform(dossier.id, 'all')
      end
      # Public formula frozen (dossier not in brouillon anymore) → unchanged
      expect(formule_champ.reload.value).to eq('25')
    end

    it 'returns silently if dossier no longer exists' do
      dossier.destroy
      expect {
        described_class.new.perform(dossier.id, 'all')
      }.not_to raise_error
    end
  end
end
