describe Logic::InArchipelOperator do
  include Logic

  let(:champ_commune_de_polynesie) { create(:champ_commune_de_polynesie, value: 'Mangareva - 98755') }
  let(:champ_code_postal_de_polynesie) { create(:champ_code_postal_de_polynesie, value: '98755 - Mangareva') }

  describe '#compute' do
    context 'commune_de_polynesie' do
      it { expect(ds_in_archipel(champ_value(champ_commune_de_polynesie.stable_id), constant('Tuamotu-Gambiers')).compute([champ_commune_de_polynesie])).to be(true) }
    end

    context 'code_postal_de_polynesie' do
      it do
        champ_code_postal_de_polynesie.update(value: '98735 - Fetuna - Raiatea')
        expect(ds_in_archipel(champ_value(champ_code_postal_de_polynesie.stable_id), constant('Iles Sous Le Vent')).compute([champ_code_postal_de_polynesie])).to be(true)
      end
    end
  end
end