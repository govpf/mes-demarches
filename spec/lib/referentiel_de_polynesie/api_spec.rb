# frozen_string_literal: true

require 'rails_helper'

describe ReferentielDePolynesie::API do
  before do
    ENV['API_BASEROW_URL'] = 'https://baserow.example.com'
    described_class.instance_variable_set(:@engine, nil)
  end

  after do
    ENV.delete('API_BASEROW_URL')
    described_class.instance_variable_set(:@engine, nil)
  end

  describe '.dlnuf_config' do
    let(:config) { { field_id: 9, field_name: 'Email', field_type: 'email' } }

    it 'délègue au moteur et met le résultat en cache' do
      allow(ReferentielDePolynesie::BaserowAPI).to receive(:dlnuf_config).with('24').and_return(config)
      expect(described_class.dlnuf_config('24')).to eq(config)
    end

    it 'met aussi en cache le mode catalogue (nil) via un sentinel', caching: true do
      allow(ReferentielDePolynesie::BaserowAPI).to receive(:dlnuf_config).with('24').and_return(nil)
      2.times { expect(described_class.dlnuf_config('24')).to be_nil }
      expect(ReferentielDePolynesie::BaserowAPI).to have_received(:dlnuf_config).once
    end

    it 'retourne nil sans moteur configuré' do
      ENV.delete('API_BASEROW_URL')
      described_class.instance_variable_set(:@engine, nil)
      expect(described_class.dlnuf_config('24')).to be_nil
    end

    it 'retourne nil pour un domain_id invalide' do
      expect(described_class.dlnuf_config('abc')).to be_nil
    end
  end

  describe '.search_with_data' do
    it 'transmet les scopes au moteur' do
      scopes = [{ field_id: 9, type: 'equal', value: 'a@b.pf' }]
      expect(ReferentielDePolynesie::BaserowAPI).to receive(:search_with_data)
        .with('24', 'q', drop_down_other: false, scopes:)
        .and_return([])
      described_class.search_with_data('24', 'q', drop_down_other: false, scopes:)
    end
  end

  describe '.table_fields' do
    let(:fields) { { 12 => { name: 'Catégorie', type: 'single_select', select_options: [] } } }

    before do
      allow(described_class).to receive(:engine).and_return(ReferentielDePolynesie::BaserowAPI)
      Rails.cache.clear
    end

    it 'délègue au moteur et met en cache', caching: true do
      expect(ReferentielDePolynesie::BaserowAPI).to receive(:table_fields).with('24').once.and_return(fields)
      2.times { expect(described_class.table_fields('24')).to eq(fields) }
    end

    it 'retourne nil (mis en cache) quand la table est inconnue', caching: true do
      expect(ReferentielDePolynesie::BaserowAPI).to receive(:table_fields).with('99').once.and_return(nil)
      2.times { expect(described_class.table_fields('99')).to be_nil }
    end

    it 'retourne nil pour un id invalide sans appeler le moteur' do
      expect(ReferentielDePolynesie::BaserowAPI).not_to receive(:table_fields)
      expect(described_class.table_fields('0')).to be_nil
    end
  end
end
