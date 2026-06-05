# frozen_string_literal: true

RSpec.describe 'Query referentielsDePolynesie', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }
  let(:query) do
    <<-GRAPHQL
    query {
      referentielsDePolynesie {
        id
        nom
      }
    }
    GRAPHQL
  end

  subject { API::V2::Schema.execute(query, variables: {}, context:) }
  let(:data) { subject['data'] }

  before do
    allow(ReferentielDePolynesie::API).to receive(:available_tables).and_return([
      { id: 24, name: 'Communes' },
      { id: 42, name: 'Entreprises' },
    ])
  end

  it 'retourne la liste des référentiels disponibles' do
    tables = data['referentielsDePolynesie']
    expect(tables).to contain_exactly(
      { 'id' => '24', 'nom' => 'Communes' },
      { 'id' => '42', 'nom' => 'Entreprises' }
    )
  end

  context 'sans token admin (administrateur_id absent du contexte)' do
    let(:context) { { procedure_ids: [], write_access: false } }

    it "retourne une erreur d'authentification" do
      expect(subject['errors']).to be_present
      expect(subject['errors'].first['message']).to include('nouveau format')
    end
  end
end
