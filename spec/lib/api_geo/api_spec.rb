# frozen_string_literal: true

require 'spec_helper'

describe APIGeo::API do
  describe '.nationalites', vcr: { cassette_name: 'api_geo_nationalites' } do
    subject { described_class.nationalites }
    let(:nationalites) {
      JSON.parse(File.read('app/lib/api_geo/nationalites.json'), symbolize_names: true)
    }

    it { is_expected.to eq nationalites }
  end

  describe '.polynesian_cities', vcr: { cassette_name: 'api_geo_polynesian_cities' } do
    subject { described_class.polynesian_cities }
    it { expect(subject.size).to eq(256) }
  end
end
