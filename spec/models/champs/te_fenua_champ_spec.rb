# frozen_string_literal: true

describe Champs::TeFenuaChamp do
  let(:types_de_champ_public) { [{ type: :te_fenua, options: { parcelles: '1' } }] }
  let(:procedure) { create(:procedure, types_de_champ_public:) }
  let(:dossier) { create(:dossier, procedure:) }
  let(:champ) { dossier.champs.first }
  let(:polygon) do
    { type: 'Polygon', coordinates: [[[-149.56, -17.53], [-149.55, -17.53], [-149.55, -17.54], [-149.56, -17.53]]] }
  end

  def geo_json(label:, id: 'parcelles 1')
    {
      parcelles: {
        type: 'FeatureCollection',
        features: [{ type: 'Feature', id:, geometry: polygon, properties: { label:, commune: 'Papeete', surface: 120 } }],
      },
    }.to_json
  end

  describe 'nettoyage HTML de la valeur' do
    it 'retire les chevrons des propriétés et des identifiants' do
      champ.update!(value: geo_json(label: '<img src=x onerror=alert(1)>', id: "<b>parcelles 1</b>"))

      feature = champ.reload.parcelles.first
      expect(feature[:properties][:label]).to eq('img src=x onerror=alert(1)')
      expect(feature[:id]).to eq('bparcelles 1/b')
      expect(champ.value).not_to match(/[<>]/)
    end

    it 'conserve à l’identique une valeur sans HTML' do
      value = geo_json(label: "Parcelle AB12 - Fa'a'ā")
      champ.update!(value:)

      expect(champ.reload.value).to eq(value)
      expect(champ.parcelles.first[:properties]).to eq(label: "Parcelle AB12 - Fa'a'ā", commune: 'Papeete', surface: 120)
    end

    it 'nettoie aussi les propriétés recopiées dans les geo_areas' do
      champ.update!(value: geo_json(label: '<script>alert(1)</script>'))

      expect(champ.reload.geo_areas.first.properties['label']).to eq('scriptalert(1)/script')
    end
  end
end
