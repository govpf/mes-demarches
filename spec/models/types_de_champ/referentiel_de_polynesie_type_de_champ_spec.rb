# frozen_string_literal: true

describe TypesDeChamp::ReferentielDePolynesieTypeDeChamp do
  let(:procedure) { create(:procedure, types_de_champ_public:) }
  let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, drop_down_other: }] }
  let(:type_de_champ) { procedure.active_revision.types_de_champ.first }
  let(:dossier) { create(:dossier, procedure:) }
  let(:champ) { dossier.project_champs_public.first }
  let(:drop_down_other) { nil }

  before do
    champ.update!(value: 'Papeete', external_id: '12345')
    champ.update_external_data!(data: {
      'code_postal' => '98714', 'archipel' => 'Iles du Vent', 'ile' => 'Tahiti',
    })
    champ.reload
  end

  describe '#champ_value_for_tag' do
    context 'with value_json (upstream mode)' do
      before do
        type_de_champ.update!(referentiel_mapping: {
          '$.code_postal' => { 'type' => 'string', 'libelle' => 'code_postal', 'display_instructeur' => '1' },
          '$.archipel' => { 'type' => 'string', 'libelle' => 'archipel', 'display_instructeur' => '1' },
          '$.ile' => { 'type' => 'string', 'libelle' => 'ile', 'display_instructeur' => '1' },
        })
        # value_json is computed by update_external_data!
      end

      it { expect(type_de_champ.champ_value_for_tag(champ, :value)).to eq('Papeete') }

      it 'returns custom column values from value_json' do
        expect(type_de_champ.champ_value_for_tag(champ, :code_postal)).to eq('98714')
        expect(type_de_champ.champ_value_for_tag(champ, :archipel)).to eq('Iles du Vent')
        expect(type_de_champ.champ_value_for_tag(champ, :ile)).to eq('Tahiti')
      end

      it { expect(type_de_champ.champ_value_for_tag(champ, :inexistant)).to eq('') }
    end

    context 'with legacy data (fallback mode)' do
      it { expect(type_de_champ.champ_value_for_tag(champ, :value)).to eq('Papeete') }

      it 'returns custom column values from normalized_data' do
        expect(type_de_champ.champ_value_for_tag(champ, :code_postal)).to eq('98714')
        expect(type_de_champ.champ_value_for_tag(champ, :archipel)).to eq('Iles du Vent')
        expect(type_de_champ.champ_value_for_tag(champ, :ile)).to eq('Tahiti')
      end

      it { expect(type_de_champ.champ_value_for_tag(champ, :inexistant)).to eq('') }
    end

    context 'with nil data' do
      before { champ.update(data: nil) }

      it 'handles missing data gracefully' do
        expect(type_de_champ.champ_value_for_tag(champ, :code_postal)).to eq('')
        expect(type_de_champ.champ_value_for_tag(champ, :value)).to eq('Papeete')
      end
    end
  end

  describe '#champ_value_for_export' do
    it 'exports main value' do
      expect(type_de_champ.champ_value_for_export(champ, :value)).to eq('Papeete')
    end

    it 'exports custom column values' do
      expect(type_de_champ.champ_value_for_export(champ, :code_postal)).to eq('98714')
      expect(type_de_champ.champ_value_for_export(champ, :archipel)).to eq('Iles du Vent')
    end
  end

  describe 'error handling' do
    context 'with nil data' do
      before { champ.update(data: nil) }

      it 'returns empty string for custom columns' do
        expect(type_de_champ.champ_value_for_tag(champ, :code_postal)).to eq('')
        expect(type_de_champ.champ_value_for_export(champ, :archipel)).to eq('')
      end

      it 'still returns main value' do
        expect(type_de_champ.champ_value_for_tag(champ, :value)).to eq('Papeete')
      end
    end

    context 'with Baserow API error' do
      before do
        allow_any_instance_of(TypesDeChamp::ReferentielDePolynesieTypeDeChamp)
          .to receive(:fetch_instructeur_fields_from_baserow)
          .and_raise(StandardError, 'Connection timeout')
      end

      it 'handles error gracefully in paths' do
        expect { type_de_champ.dynamic_type.paths }.not_to raise_error
        expect(type_de_champ.dynamic_type.paths.size).to eq(1) # Only :value
      end
    end
  end

  describe '#drop_down_other?' do
    context 'when drop_down_other is nil' do
      let(:drop_down_other) { nil }

      it { expect(type_de_champ.drop_down_other?).to be false }
    end

    context 'when drop_down_other is "0"' do
      let(:drop_down_other) { "0" }

      it { expect(type_de_champ.drop_down_other?).to be false }
    end

    context 'when drop_down_other is false' do
      let(:drop_down_other) { false }

      it { expect(type_de_champ.drop_down_other?).to be false }
    end

    context 'when drop_down_other is "1"' do
      let(:drop_down_other) { "1" }

      it { expect(type_de_champ.drop_down_other?).to be true }
    end

    context 'when drop_down_other is true' do
      let(:drop_down_other) { true }

      it { expect(type_de_champ.drop_down_other?).to be true }
    end
  end

  describe 'champ#drop_down_other?' do
    context 'when drop_down_other is enabled' do
      let(:drop_down_other) { true }

      it 'delegates to type_de_champ' do
        expect(champ.drop_down_other?).to be true
      end
    end

    context 'when drop_down_other is disabled' do
      let(:drop_down_other) { false }

      it 'delegates to type_de_champ' do
        expect(champ.drop_down_other?).to be false
      end
    end
  end
end
