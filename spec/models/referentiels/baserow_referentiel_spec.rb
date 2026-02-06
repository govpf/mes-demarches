# frozen_string_literal: true

describe Referentiels::BaserowReferentiel do
  describe 'validations' do
    it 'validates presence of table_id' do
      referentiel = build(:baserow_referentiel, test_data: nil)
      expect(referentiel).not_to be_valid
      expect(referentiel.errors[:table_id]).to include("doit être rempli")
    end

    it 'validates table_id is a positive integer' do
      referentiel = build(:baserow_referentiel, test_data: '0')
      expect(referentiel).not_to be_valid
      expect(referentiel.errors[:table_id]).to include("doit être supérieur à 0")
    end

    it 'validates table_id is numeric' do
      referentiel = build(:baserow_referentiel, test_data: 'abc')
      expect(referentiel).not_to be_valid
      expect(referentiel.errors[:table_id]).to include("n'est pas un nombre")
    end

    it 'is valid with a positive integer table_id' do
      referentiel = build(:baserow_referentiel, test_data: '24')
      expect(referentiel).to be_valid
    end
  end

  describe '#table_id alias' do
    let(:referentiel) { build(:baserow_referentiel, test_data: '42') }

    it 'aliases table_id to test_data' do
      expect(referentiel.table_id).to eq('42')
    end

    it 'allows setting via table_id=' do
      referentiel.table_id = '99'
      expect(referentiel.test_data).to eq('99')
    end
  end

  describe '#configured?' do
    it 'returns true when table_id is a positive integer' do
      referentiel = build(:baserow_referentiel, test_data: '24')
      expect(referentiel.configured?).to be true
    end

    it 'returns false when table_id is blank' do
      referentiel = build(:baserow_referentiel, test_data: nil)
      expect(referentiel.configured?).to be false
    end

    it 'returns false when table_id is 0' do
      referentiel = build(:baserow_referentiel, test_data: '0')
      expect(referentiel.configured?).to be false
    end
  end

  describe '#ready?' do
    let(:referentiel) { build(:baserow_referentiel, test_data: '24') }

    context 'when configured and baserow_config is present' do
      before do
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:config)
          .with('24')
          .and_return({ 'Champs usager' => 'Nom' })
      end

      it 'returns true' do
        expect(referentiel.ready?).to be true
      end
    end

    context 'when configured but baserow_config is nil' do
      before do
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:config)
          .with('24')
          .and_return(nil)
      end

      it 'returns false' do
        expect(referentiel.ready?).to be false
      end
    end

    context 'when not configured' do
      let(:referentiel) { build(:baserow_referentiel, test_data: nil) }

      it 'returns false' do
        expect(referentiel.ready?).to be false
      end
    end
  end

  describe '#url' do
    let(:referentiel) { build(:baserow_referentiel, test_data: '24') }

    it 'returns a baserow:// URL with table_id and {id} placeholder' do
      expect(referentiel.url).to eq('baserow://24/{id}')
    end
  end

  describe '#headers' do
    let(:referentiel) { build(:baserow_referentiel, test_data: '24') }

    context 'when baserow_config is present' do
      let(:config) do
        {
          'Champs usager' => 'Nom,Archipel',
          'Champs instructeur' => 'Code,Archipel'
        }
      end

      let(:model) do
        [
          { 'id' => 1, 'name' => 'Nom' },
          { 'id' => 2, 'name' => 'Archipel' },
          { 'id' => 3, 'name' => 'Code' }
        ]
      end

      before do
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:config)
          .with('24')
          .and_return(config)
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:fields)
          .with(config)
          .and_return(model)
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:field_names)
          .with(model, 'Nom,Archipel')
          .and_return(['Nom', 'Archipel'])
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:field_names)
          .with(model, 'Code,Archipel')
          .and_return(['Code', 'Archipel'])
      end

      it 'returns unique headers from usager and instructeur fields' do
        expect(referentiel.headers).to eq(['Nom', 'Archipel', 'Code'])
      end
    end

    context 'when baserow_config is nil' do
      before do
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:config)
          .with('24')
          .and_return(nil)
      end

      it 'returns empty array' do
        expect(referentiel.headers).to eq([])
      end
    end
  end

  describe '#headers_with_path' do
    let(:referentiel) { build(:baserow_referentiel, test_data: '24') }

    before do
      allow(referentiel).to receive(:headers).and_return(['Nom', 'Code'])
    end

    it 'returns headers with JSONPath format' do
      expect(referentiel.headers_with_path).to eq([
        ['Nom', '$.row.Nom'],
        ['Code', '$.row.Code']
      ])
    end
  end

  describe '#last_response_status' do
    let(:referentiel) { build(:baserow_referentiel, test_data: '24') }

    context 'when last_response has status' do
      before { referentiel.last_response = { 'status' => 200 } }

      it 'returns the status' do
        expect(referentiel.last_response_status).to eq(200)
      end
    end

    context 'when last_response is nil' do
      before { referentiel.last_response = nil }

      it 'returns 500 as default' do
        expect(referentiel.last_response_status).to eq(500)
      end
    end

    context 'when last_response has no status key' do
      before { referentiel.last_response = { 'body' => {} } }

      it 'returns 500 as default' do
        expect(referentiel.last_response_status).to eq(500)
      end
    end
  end

  describe 'class methods' do
    describe '.csv_available?' do
      it 'returns false' do
        expect(described_class.csv_available?).to be false
      end
    end

    describe '.autocomplete_available?' do
      it 'returns true' do
        expect(described_class.autocomplete_available?).to be true
      end
    end
  end

  describe 'name generation' do
    let(:referentiel) { build(:baserow_referentiel, test_data: '24', name: nil) }

    it 'generates a UUID name on save if name is blank' do
      referentiel.save!
      expect(referentiel.name).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'keeps existing name if provided' do
      referentiel.name = 'Mon référentiel'
      referentiel.save!
      expect(referentiel.name).to eq('Mon référentiel')
    end
  end
end
