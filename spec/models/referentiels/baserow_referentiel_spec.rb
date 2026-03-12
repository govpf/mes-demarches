# frozen_string_literal: true

describe Referentiels::BaserowReferentiel do
  describe 'validations' do
    it 'validates presence of url' do
      referentiel = build(:baserow_referentiel, url: nil)
      expect(referentiel).not_to be_valid
      expect(referentiel.errors[:url]).to include("doit être rempli")
    end

    it 'validates url format with invalid value' do
      referentiel = build(:baserow_referentiel, url: 'invalid')
      expect(referentiel).not_to be_valid
      expect(referentiel.errors[:url]).to include("doit être au format baserow://TABLE_ID")
    end

    it 'validates url format with zero table_id' do
      referentiel = build(:baserow_referentiel, url: 'baserow://0')
      expect(referentiel).to be_valid # format is valid, configured? will return false
    end

    it 'is valid with a proper baserow:// URL' do
      referentiel = build(:baserow_referentiel, url: 'baserow://24')
      expect(referentiel).to be_valid
    end
  end

  describe '#table_id getter/setter' do
    let(:referentiel) { build(:baserow_referentiel, url: 'baserow://42') }

    it 'derives table_id from url' do
      expect(referentiel.table_id).to eq('42')
    end

    it 'allows setting via table_id=' do
      referentiel.table_id = '99'
      expect(referentiel.url).to eq('baserow://99')
      expect(referentiel.table_id).to eq('99')
    end

    it 'sets url to nil when table_id is blank' do
      referentiel.table_id = ''
      expect(referentiel.url).to be_nil
    end
  end

  describe '#configured?' do
    it 'returns true when mode and table_id are present' do
      referentiel = build(:baserow_referentiel, url: 'baserow://24', mode: 'autocomplete')
      expect(referentiel.configured?).to be true
    end

    it 'returns true in exact_match mode with a valid table_id' do
      referentiel = build(:baserow_referentiel, url: 'baserow://24', mode: 'exact_match')
      expect(referentiel.configured?).to be true
    end

    it 'returns false when mode is nil' do
      referentiel = build(:baserow_referentiel, url: 'baserow://24', mode: nil)
      expect(referentiel.configured?).to be false
    end

    it 'returns false when url is blank' do
      referentiel = build(:baserow_referentiel, url: nil)
      expect(referentiel.configured?).to be false
    end

    it 'returns false when table_id is 0' do
      referentiel = build(:baserow_referentiel, url: 'baserow://0')
      expect(referentiel.configured?).to be false
    end
  end

  describe '#ready?' do
    let(:referentiel) { build(:baserow_referentiel, url: 'baserow://24') }

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
      let(:referentiel) { build(:baserow_referentiel, url: nil) }

      it 'returns false' do
        expect(referentiel.ready?).to be false
      end
    end
  end

  describe '#headers' do
    let(:referentiel) { build(:baserow_referentiel, url: 'baserow://24') }

    context 'when baserow_config is present' do
      let(:config) do
        {
          'Champs usager' => '1,2',
          'Champs instructeur' => '3,2'
        }
      end

      let(:model) do
        {
          1 => { name: 'Nom', type: 'text' },
          2 => { name: 'Archipel', type: 'text' },
          3 => { name: 'Code', type: 'number' }
        }
      end

      before do
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:config)
          .with('24')
          .and_return(config)
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:fields)
          .with(config)
          .and_return(model)
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
    let(:referentiel) { build(:baserow_referentiel, url: 'baserow://24') }

    before do
      allow(referentiel).to receive(:headers).and_return(['Nom', 'Code'])
    end

    it 'returns headers with flat JSONPath format' do
      expect(referentiel.headers_with_path).to eq([
        ['Nom', '$.Nom'],
        ['Code', '$.Code']
      ])
    end
  end

  describe '#last_response_status' do
    let(:referentiel) { build(:baserow_referentiel, url: 'baserow://24') }

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
  end

  describe 'name generation' do
    let(:referentiel) { build(:baserow_referentiel, url: 'baserow://24', name: nil) }

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
