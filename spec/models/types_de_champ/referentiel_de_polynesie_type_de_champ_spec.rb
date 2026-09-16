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

    # pf: la table méta Baserow peut lister une colonne supprimée depuis (id périmé) ; l’éditeur
    # de la démarche ne doit pas tomber pour autant (undefined method 'to_sym' for nil)
    context 'with a stale column id in the Baserow config' do
      before do
        type_de_champ.update!(options: type_de_champ.options.merge('table_id' => '19'))
        allow(ReferentielDePolynesie::API).to receive(:engine).and_return(ReferentielDePolynesie::BaserowAPI)
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:config).and_return({ 'Table' => '19', 'Champs instructeur' => '5,9382,6' })
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:fields).and_return({ 5 => { name: 'Nom', type: 'text' }, 6 => { name: 'Code', type: 'text' } })
      end

      it 'skips the missing column in paths' do
        expect(type_de_champ.dynamic_type.paths.map { _1[:path] }).to eq([:value, :Nom, :Code])
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

  describe 'referentiel_filter (cascade)' do
    let(:type_de_champ) { build(:type_de_champ_referentiel_de_polynesie, table_id: '24', no_coordinate: true) }
    let(:fields) { { 12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 1, value: 'Semences' }] } } }

    before { allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(fields) }

    it 'est absent par défaut' do
      expect(type_de_champ.referentiel_filter).to be_nil
      expect(type_de_champ.referentiel_filter?).to be(false)
    end

    it 'est conservé par clean_options pour ce type' do
      type_de_champ.referentiel_filter = { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/7' }
      expect(type_de_champ.clean_options.keys).to include('referentiel_filter')
      expect(type_de_champ.referentiel_filter?).to be(true)
    end

    describe '#referentiel_filter_form=' do
      it 'enregistre la config et résout le nom de la colonne Baserow' do
        type_de_champ.referentiel_filter_form = { 'enabled' => '1', 'baserow_field_id' => '12', 'pilot_column_id' => 'type_de_champ/7' }
        expect(type_de_champ.referentiel_filter).to eq(
          'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/7'
        )
      end

      it 'efface la config quand la case est décochée' do
        type_de_champ.referentiel_filter = { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/7' }
        type_de_champ.referentiel_filter_form = { 'baserow_field_id' => '12', 'pilot_column_id' => 'type_de_champ/7' }
        expect(type_de_champ.referentiel_filter).to be_nil
      end

      it 'n\'enregistre rien si une des deux listes est vide' do
        type_de_champ.referentiel_filter_form = { 'enabled' => '1', 'baserow_field_id' => '', 'pilot_column_id' => 'type_de_champ/7' }
        expect(type_de_champ.referentiel_filter).to be_nil
      end

      # pf: la table Baserow a changé sous les pieds de la config (colonne supprimée) : garder
      # le filtre reviendrait à ne plus laisser passer aucune ligne.
      it 'efface la config quand la colonne est absente de la table' do
        type_de_champ.referentiel_filter = { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/7' }
        type_de_champ.referentiel_filter_form = { 'enabled' => '1', 'baserow_field_id' => '99', 'pilot_column_id' => 'type_de_champ/7' }
        expect(type_de_champ.referentiel_filter).to be_nil
      end

      it 'garde le nom en cache si Baserow est injoignable' do
        allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(nil)
        type_de_champ.referentiel_filter = { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/7' }
        type_de_champ.referentiel_filter_form = { 'enabled' => '1', 'baserow_field_id' => '12', 'pilot_column_id' => 'type_de_champ/9' }
        expect(type_de_champ.referentiel_filter).to eq(
          'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/9'
        )
      end
    end
  end
end
