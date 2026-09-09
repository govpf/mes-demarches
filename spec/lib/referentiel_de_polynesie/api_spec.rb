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
    it 'transmet le scope au moteur' do
      scope = { field_id: 9, value: 'a@b.pf' }
      expect(ReferentielDePolynesie::BaserowAPI).to receive(:search_with_data)
        .with('24', 'q', drop_down_other: false, scope:)
        .and_return([])
      described_class.search_with_data('24', 'q', drop_down_other: false, scope:)
    end
  end
end
