# frozen_string_literal: true

RSpec.describe 'Query referentielColonnes', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }
  # pf: API.engine retourne la CLASSE BaserowAPI (pas une instance) — utiliser class_double
  let(:engine) { class_double(ReferentielDePolynesie::BaserowAPI) }
  let(:query) do
    <<-GRAPHQL
    query($tableId: String!) {
      referentielColonnes(tableId: $tableId) {
        nom
        typeMapping
      }
    }
    GRAPHQL
  end
  let(:variables) { { tableId: '24' } }

  subject { API::V2::Schema.execute(query, variables:, context:) }
  let(:data) { subject['data'] }

  before do
    allow(ReferentielDePolynesie::API).to receive(:engine).and_return(engine)
    allow(engine).to receive(:config).with('24').and_return({ 'Table' => '24', 'Token' => 't' })
    allow(engine).to receive(:fields).and_return({
      1 => { name: 'RaisonSociale', type: 'text' },
      2 => { name: 'Effectif', type: 'number', number_decimal_places: 0 },
    })
  end

  it 'retourne les colonnes avec leur type de mapping' do
    colonnes = data['referentielColonnes']
    expect(colonnes).to contain_exactly(
      { 'nom' => 'RaisonSociale', 'typeMapping' => 'string' },
      { 'nom' => 'Effectif', 'typeMapping' => 'integer_number' }
    )
  end

  context 'Baserow indisponible (engine nil)' do
    before { allow(ReferentielDePolynesie::API).to receive(:engine).and_return(nil) }

    it 'retourne une erreur GraphQL' do
      expect(subject['errors']).to be_present
      expect(subject['errors'].first['message']).to include("Baserow n'est pas configuré")
    end
  end

  context 'sans token admin (administrateur_id absent du contexte)' do
    let(:context) { { procedure_ids: [], write_access: false } }

    it "retourne une erreur d'authentification" do
      expect(subject['errors']).to be_present
      expect(subject['errors'].first['message']).to include('nouveau format')
    end
  end
end
