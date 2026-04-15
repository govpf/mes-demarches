# frozen_string_literal: true

describe Logic::InArchipelOperator do
  include Logic

  let(:procedure) do
    create(:procedure, :published, types_de_champ_public: [
      { type: :commune_de_polynesie, libelle: 'Commune PF' },
      { type: :code_postal_de_polynesie, libelle: 'Code Postal PF' }
    ])
  end
  let(:dossier) { create(:dossier, :with_populated_champs, procedure:) }

  let(:tdc_commune) { procedure.active_revision.types_de_champ_public.find(&:commune_de_polynesie?) }
  let(:tdc_code_postal) { procedure.active_revision.types_de_champ_public.find(&:code_postal_de_polynesie?) }

  let(:champ_commune_de_polynesie) { dossier.champs.find { _1.stable_id == tdc_commune.stable_id }.tap { _1.update!(value: 'Mangareva - 98755') } }
  let(:champ_code_postal_de_polynesie) { dossier.champs.find { _1.stable_id == tdc_code_postal.stable_id }.tap { _1.update!(value: '98755 - Mangareva') } }

  describe '#compute' do
    context 'commune_de_polynesie' do
      it { expect(ds_in_archipel(champ_value(champ_commune_de_polynesie.stable_id), constant('Tuamotu-Gambiers')).compute([champ_commune_de_polynesie])).to be(true) }
    end

    context 'code_postal_de_polynesie' do
      it do
        champ_code_postal_de_polynesie.update!(value: '98735 - Fetuna - Raiatea')
        expect(ds_in_archipel(champ_value(champ_code_postal_de_polynesie.stable_id), constant('Iles Sous Le Vent')).compute([champ_code_postal_de_polynesie])).to be(true)
      end
    end
  end
end
