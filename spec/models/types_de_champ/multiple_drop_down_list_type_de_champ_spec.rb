# frozen_string_literal: true

describe TypesDeChamp::MultipleDropDownListTypeDeChamp do
  describe '#columns' do
    let(:referentiel) { create(:csv_referentiel, :with_items) }
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :multiple_drop_down_list, drop_down_mode: 'advanced', referentiel: }]) }
    let(:type_de_champ) { procedure.draft_revision.types_de_champ_public.first }

    subject(:columns) { type_de_champ.columns(procedure:) }

    context 'mode avancé avec référentiel' do
      it 'renvoie un tableau contenant la MultipleDropDownColumn' do
        expect(columns).to be_an(Array)
        expect(columns).to contain_exactly(an_instance_of(Columns::MultipleDropDownColumn))
      end
    end

    context 'mode avancé sans référentiel' do
      let(:referentiel) { nil }

      it { expect(columns).to eq([]) }
    end
  end
end
