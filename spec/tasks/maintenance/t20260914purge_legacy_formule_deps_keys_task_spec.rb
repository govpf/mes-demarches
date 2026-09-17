# frozen_string_literal: true

require "rails_helper"

module Maintenance
  RSpec.describe T20260914purgeLegacyFormuleDepsKeysTask do
    let(:task) { described_class.new }
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :formule, formule_expression: 'AGE({dossier_depose_at})' }]) }
    let(:formule_tdc) { procedure.draft_revision.types_de_champ_public.first }
    let(:formule_deps) { formule_tdc.formule_deps }

    before do
      # état hérité des anciens flags, tel qu'il subsiste en base après la migration 20260522174323
      formule_tdc.update_column(:options, formule_tdc.options.merge('clock_dependent' => true, 'state_dependent' => false))
    end

    describe "#collection" do
      let!(:clean_tdc) { create(:type_de_champ_formule) }
      let!(:only_state_tdc) do
        create(:type_de_champ_formule).tap { |tdc| tdc.update_column(:options, tdc.options.merge('state_dependent' => true)) }
      end

      it "ne retient que les TDC formule portant au moins une clé legacy" do
        expect(task.collection).to contain_exactly(formule_tdc, only_state_tdc)
      end
    end

    describe "#process" do
      it "retire les deux clés legacy sans toucher au reste des options" do
        expect(formule_tdc.reload.options).to include('clock_dependent', 'state_dependent')

        task.process(formule_tdc)

        options = formule_tdc.reload.options
        expect(options).not_to include('clock_dependent', 'state_dependent')
        expect(formule_deps).to include('has_clock' => true, 'has_state' => true)
        expect(options['formule_deps']).to eq(formule_deps)
        expect(options['formule_expression']).to eq('AGE({dossier_depose_at})')
      end

      it "n'écrit que la purge des clés, sans callbacks" do
        expect { task.process(formule_tdc) }.not_to change { formule_tdc.reload.updated_at }
      end
    end
  end
end
