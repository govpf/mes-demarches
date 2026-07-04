# frozen_string_literal: true

RSpec.describe 'Query aideFormule', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:procedure) do
    create(:procedure, administrateurs: [admin], types_de_champ_public: [
      { type: :integer_number, libelle: 'Montant' },
      { type: :formule, libelle: 'Total' },
    ])
  end
  let(:formule) { procedure.draft_revision.types_de_champ.find(&:formule?) }
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }
  let(:query) do
    <<-GRAPHQL
    query($demarche: FindDemarcheInput!, $stableId: String!) {
      aideFormule(demarche: $demarche, stableId: $stableId)
    }
    GRAPHQL
  end
  let(:variables) { { demarche: { number: procedure.id }, stableId: formule.stable_id.to_s } }

  subject { API::V2::Schema.execute(query, variables:, context:) }
  let(:data) { subject['data'] }

  it 'renvoie la documentation de formule' do
    doc = data['aideFormule']
    expect(doc).to be_present
    expect(doc).to include('SOMME') # une fonction whitelistée documentée
  end

  context 'champ non-formule' do
    let(:non_formule) { procedure.draft_revision.types_de_champ.find { !_1.formule? } }
    let(:variables) { { demarche: { number: procedure.id }, stableId: non_formule.stable_id.to_s } }

    it 'remonte une erreur' do
      expect(subject['errors']).to be_present
    end
  end
end
