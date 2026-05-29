# frozen_string_literal: true

require "rails_helper"

module Maintenance
  RSpec.describe PopulateNumeroDnValueJSONTask do
    describe "#process" do
      let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :numero_dn }]) }
      let(:dossier) { create(:dossier, procedure:) }
      let(:champ) { dossier.champs.first }

      before do
        # simule un vieux champ : seul le packing legacy dans `value`, pas de value_json
        champ.update_columns(value: JSON.generate(['1234567', '2015-06-15']), value_json: nil)
      end

      it 'reconstruit value_json depuis le packing legacy' do
        described_class.process(champ)
        champ.reload
        expect(champ.value_json['numero_dn']).to eq('1234567')
        expect(champ.value_json['date_de_naissance']).to eq('2015-06-15')
      end
    end
  end
end
