# frozen_string_literal: true

describe Champs::CommuneDePolynesieChamp do
  let(:sample) { APIGeo::API.communes_de_polynesie.find { !_1.start_with?('---') } }
  let(:champ) { described_class.new(value: sample) }

  describe 'cache value_json peuplé à la sauvegarde (on_value_change)' do
    before { champ.send(:on_value_change) }

    it 'remplit ile, commune, archipel, code_postal depuis APIGeo' do
      city = APIGeo::API.commune_by_city_postal_code(sample)
      expect(champ.ile).to eq(city[:ile])
      expect(champ.commune).to eq(city[:commune])
      expect(champ.archipel).to eq(city[:archipel])
      expect(champ.code_postal).to eq(city[:code_postal])
    end

    it 'vide le cache quand value est blank' do
      champ.value = nil
      champ.send(:on_value_change)
      expect(champ.ile).to be_nil
      expect(champ.code_postal).to be_nil
      expect(champ.archipel).to be_nil
      expect(champ.commune).to be_nil
    end
  end
end
