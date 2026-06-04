# frozen_string_literal: true

RSpec.describe 'Query referentielChampConfig', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:procedure) { create(:procedure, administrateurs: [admin], types_de_champ_public: [{ type: :referentiel_de_polynesie, libelle: 'Entreprise', table_id: '24' }]) }
  let(:tdc) { procedure.draft_revision.types_de_champ.first }
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }
  # pf: API.engine retourne la CLASSE BaserowAPI (pas une instance) — utiliser class_double
  let(:engine) { class_double(ReferentielDePolynesie::BaserowAPI) }
  let(:query) do
    <<-GRAPHQL
    query($demarche: FindDemarcheInput!, $stableId: String!) {
      referentielChampConfig(demarche: $demarche, stableId: $stableId) {
        tableId
        colonnes { nom typeMapping }
        mappingActuel
      }
    }
    GRAPHQL
  end
  let(:variables) { { demarche: { number: procedure.id }, stableId: tdc.stable_id.to_s } }
  subject { API::V2::Schema.execute(query, variables:, context:) }
  let(:data) { subject['data'] }

  before do
    allow(ReferentielDePolynesie::API).to receive(:engine).and_return(engine)
    allow(engine).to receive(:config).and_return({ 'Table' => '24', 'Token' => 't' })
    allow(engine).to receive(:fields).and_return({ 1 => { name: 'RaisonSociale', type: 'text' } })
  end

  it 'retourne table_id + colonnes Baserow' do
    cfg = data['referentielChampConfig']
    expect(cfg['tableId']).to eq('24')
    expect(cfg['colonnes']).to include({ 'nom' => 'RaisonSociale', 'typeMapping' => 'string' })
  end

  context 'Baserow indisponible' do
    before { allow(ReferentielDePolynesie::API).to receive(:engine).and_return(nil) }
    it 'remonte une erreur' do
      expect(subject['errors']).to be_present
    end
  end
end
