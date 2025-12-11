# frozen_string_literal: true

describe TypesDeChamp::ReferentielDePolynesieTypeDeChamp do
  let(:procedure) { create(:procedure, types_de_champ_public:) }
  let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie }] }
  let(:type_de_champ) { procedure.active_revision.types_de_champ.first }
  let(:dossier) { create(:dossier, procedure:) }
  let(:champ) { dossier.project_champs_public.first }

  before do
    champ.update!(value: 'Papeete', external_id: '12345')
    champ.update_with_external_data!(data: {
      'row' => { 'code_postal' => '98714', 'archipel' => 'Iles du Vent', 'ile' => 'Tahiti' },
      'instructeur_fields' => ['code_postal', 'archipel', 'ile']
    })
    champ.reload
  end

  describe '#champ_value_for_tag' do
    it { expect(type_de_champ.champ_value_for_tag(champ, :value)).to eq('Papeete') }

    it 'returns custom column values' do
      expect(type_de_champ.champ_value_for_tag(champ, :code_postal)).to eq('98714')
      expect(type_de_champ.champ_value_for_tag(champ, :archipel)).to eq('Iles du Vent')
      expect(type_de_champ.champ_value_for_tag(champ, :ile)).to eq('Tahiti')
    end

    it { expect(type_de_champ.champ_value_for_tag(champ, :inexistant)).to eq('') }

    context 'with nil data' do
      before { champ.update(data: nil) }

      it 'handles missing data gracefully' do
        expect(type_de_champ.champ_value_for_tag(champ, :code_postal)).to eq('')
        expect(type_de_champ.champ_value_for_tag(champ, :value)).to eq('Papeete')
      end
    end
  end

  describe '#champ_value_for_export' do
    it 'uses same logic as champ_value_for_tag' do
      expect(type_de_champ.champ_value_for_export(champ, :code_postal))
        .to eq(type_de_champ.champ_value_for_tag(champ, :code_postal))
    end
  end
end
