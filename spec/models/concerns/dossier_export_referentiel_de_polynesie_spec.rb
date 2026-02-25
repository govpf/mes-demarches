# frozen_string_literal: true

describe DossierExportConcern do
  describe 'export with referentiel_de_polynesie multi-columns' do
    let(:procedure) { create(:procedure, types_de_champ_public:) }
    let(:types_de_champ_public) { [{ type: :referentiel_de_polynesie, libelle: 'Commune', options: { table_id: 123 } }] }
    let(:dossier) { create(:dossier, :en_instruction, procedure:) }
    let(:type_de_champ) { procedure.active_revision.types_de_champ.first }
    let(:champ) { dossier.project_champs_public.first }

    before do
      allow_any_instance_of(TypesDeChamp::ReferentielDePolynesieTypeDeChamp)
        .to receive(:fetch_instructeur_fields)
        .and_return(['code_postal', 'archipel', 'ile'])

      champ.update!(value: 'Papeete', external_id: '12345')
      champ.update_external_data!(data: {
        'code_postal' => '98714', 'archipel' => 'Iles du Vent', 'ile' => 'Tahiti'
      })
      champ.reload
    end

    describe '#champ_values_for_export' do
      let(:export_values) { dossier.champ_values_for_export([type_de_champ], format: :csv) }

      it { expect(export_values.size).to eq(4) }

      it { expect(export_values.first).to eq(['Commune', 'Papeete']) }

      it 'exports custom columns with labels and values' do
        values = export_values.to_h
        expect(values).to include(
          'Commune (code_postal)' => '98714',
          'Commune (archipel)' => 'Iles du Vent',
          'Commune (ile)' => 'Tahiti'
        )
      end
    end
  end
end
