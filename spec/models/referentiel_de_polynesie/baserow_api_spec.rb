require 'rails_helper'
require 'webmock/rspec'

RSpec.describe ReferentielDePolynesie::BaserowAPI, type: :model do
  describe '#search' do
    it 'searches in a Baserow table and returns the result', vcr: { cassette_name: 'baserow/baserow_search' } do
      allow(ReferentielDePolynesie::BaserowAPI).to receive(:config).and_return({
        'Table' => '202600',
        'Champ de recherche' => 'search_field',
        'Token' => ENV['API_BASEROW_TOKEN'].to_s
      })

      results = ReferentielDePolynesie::BaserowAPI.search(123, "term")

      expect(results).to be_an(Array)
      expect(results.length).to be > 0
      expect(results.first).to have_key(:name)
      expect(results.first).to have_key(:id)
    end
  end

  describe '#fetch_row' do
    it 'fetches a specific line in a Baserow table', vcr: { cassette_name: 'baserow/baserow_fetch_row' } do
      allow(ReferentielDePolynesie::BaserowAPI).to receive(:config).and_return({
        'Table' => '202600',
        'Token' => ENV['API_BASEROW_TOKEN'].to_s
      })

      result = ReferentielDePolynesie::BaserowAPI.fetch_row(123, 1)

      expect(result[:row]["Nom"]).to eq("Communes de polynésie")
      expect(result[:row]["Notes"]).to eq("")
      expect(result[:row]["Actif"]).to eq(true)
      expect(result[:row]["Table"]).to eq("202578")
      expect(result[:row]["Champs usager"]).to eq("1391747,1391750,1391755,1391756")
      expect(result[:row]["Champ de recherche"]).to eq("1391747")
      expect(result[:row]["Champs instructeur"]).to eq("1391747,1391750,1391755,1391756")
    end

    it 'returns a 404 error if the row does not exist', vcr: { cassette_name: 'baserow/baserow404_error' } do
      allow(ReferentielDePolynesie::BaserowAPI).to receive(:config).and_return({
        'Table' => '202600',
        'Token' => ENV['API_BASEROW_TOKEN'].to_s
      })

      results = ReferentielDePolynesie::BaserowAPI.fetch_row(123, 99999)

      expect(results).to eq(nil)
    end
  end

  describe '#available_tables' do
    it 'fetches the available tables', vcr: { cassette_name: 'baserow/baserow_api_available_tables' } do
      allow(ReferentielDePolynesie::BaserowAPI).to receive(:config)

      results = ReferentielDePolynesie::BaserowAPI.available_tables

      expect(results).to be_an(Array)
      expect(results.first[:name]).to eq("Communes de polynésie")
      expect(results.first[:id]).to eq(1)
    end
  end
end
