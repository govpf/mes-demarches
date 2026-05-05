# frozen_string_literal: true

describe Cron::RefreshClockDependentFormulasJob do
  let(:clock_dep_procedure) {
    create(:procedure, :published, types_de_champ_public: [
      { type: :date, libelle: 'Date de naissance' },
      { type: :formule, libelle: 'Age' },
    ])
  }
  let(:clock_dep_revision) { clock_dep_procedure.active_revision }

  let(:non_clock_procedure) {
    create(:procedure, :published, types_de_champ_public: [
      { type: :integer_number, libelle: 'Prix' },
      { type: :formule, libelle: 'Double' },
    ])
  }
  let(:non_clock_revision) { non_clock_procedure.active_revision }

  before do
    # Set AGE formula on clock_dep_procedure
    formule_tdc = clock_dep_revision.types_de_champ.find(&:formule?)
    expr, _ = FormulaExpressionService.convert_to_stable_ids('AGE({Date de naissance})', clock_dep_revision)
    formule_tdc.update(formule_expression: expr)

    # Set non-clock formula on non_clock_procedure
    non_clock_tdc = non_clock_revision.types_de_champ.find(&:formule?)
    expr2, _ = FormulaExpressionService.convert_to_stable_ids('{Prix} * 2', non_clock_revision)
    non_clock_tdc.update(formule_expression: expr2)
  end

  describe '#perform' do
    it 'enqueues refresh job for brouillon dossier with clock_dependent formula (scope: all)' do
      dossier = create(:dossier, :with_populated_champs, procedure: clock_dep_procedure)
      expect(dossier.brouillon?).to be true

      expect {
        described_class.new.perform
      }.to have_enqueued_job(RefreshClockDependentFormulasDossierJob).with(dossier.id, 'all')
    end

    it 'enqueues refresh job for en_construction dossier (scope: private_only)' do
      dossier = create(:dossier, :en_construction, :with_populated_champs, procedure: clock_dep_procedure)

      expect {
        described_class.new.perform
      }.to have_enqueued_job(RefreshClockDependentFormulasDossierJob).with(dossier.id, 'private_only')
    end

    it 'does NOT enqueue a job for a terminal dossier' do
      create(:dossier, :accepte, procedure: clock_dep_procedure)

      expect {
        described_class.new.perform
      }.not_to have_enqueued_job(RefreshClockDependentFormulasDossierJob)
    end

    it 'does NOT enqueue a job for a procedure without clock_dependent formula' do
      create(:dossier, :with_populated_champs, procedure: non_clock_procedure)

      expect {
        described_class.new.perform
      }.not_to have_enqueued_job(RefreshClockDependentFormulasDossierJob)
    end

    it 'does nothing if no revision has a clock_dependent formula' do
      # Reset clock_dep formula to non-clock
      formule_tdc = clock_dep_revision.types_de_champ.find(&:formule?)
      expr, _ = FormulaExpressionService.convert_to_stable_ids('1 + 1', clock_dep_revision)
      formule_tdc.update(formule_expression: expr)

      create(:dossier, :with_populated_champs, procedure: clock_dep_procedure)

      expect {
        described_class.new.perform
      }.not_to have_enqueued_job(RefreshClockDependentFormulasDossierJob)
    end
  end
end
