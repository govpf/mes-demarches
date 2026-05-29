# frozen_string_literal: true

require "rails_helper"

module Maintenance
  RSpec.describe PopulateCommunePolynesieValueJSONTask do
    describe "#process" do
      let(:sample) { APIGeo::API.communes_de_polynesie.find { !_1.start_with?('---') } }
      let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :commune_de_polynesie }]) }
      let(:dossier) { create(:dossier, procedure:) }
      let(:champ) { dossier.champs.find(&:commune_de_polynesie?) || dossier.champs.first }

      before do
        champ.update!(value: sample)
        # simule un vieux champ : value_json sans les sous-champs normalisés
        champ.update_columns(value_json: {})
      end

      it 'repeuple value_json depuis APIGeo' do
        expect { described_class.process(champ) }
          .to change { champ.reload.value_json['ile'] }
          .from(nil)
          .to(APIGeo::API.commune_by_city_postal_code(sample)[:ile])

        expect(champ.value_json['commune']).to be_present
        expect(champ.value_json['archipel']).to be_present
        expect(champ.value_json['code_postal']).to be_present
      end
    end
  end
end
