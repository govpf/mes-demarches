# frozen_string_literal: true

RSpec.describe 'Query demarcheChamps', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:procedure) do
    create(:procedure, administrateurs: [admin], types_de_champ_public: [
      { type: :text, libelle: 'Nom' },
      { type: :integer_number, libelle: 'Âge' },
    ])
  end
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }
  let(:query) do
    <<-GRAPHQL
    query($demarche: FindDemarcheInput!) {
      demarcheChamps(demarche: $demarche) {
        stableId
        typeChamp
        libelle
        obligatoire
        prive
        parentStableId
        aCondition
      }
    }
    GRAPHQL
  end
  let(:variables) { { demarche: { number: procedure.id } } }

  subject { API::V2::Schema.execute(query, variables:, context:) }
  let(:data) { subject['data'].deep_symbolize_keys }

  it 'retourne les champs du brouillon avec leur stable_id' do
    champs = data[:demarcheChamps]
    expect(champs.map { _1[:libelle] }).to eq(['Nom', 'Âge'])
    expect(champs.map { _1[:typeChamp] }).to eq(['text', 'integer_number'])
    expect(champs.first[:stableId]).to eq(procedure.draft_revision.types_de_champ.first.stable_id.to_s)
    expect(champs.first[:aCondition]).to eq(false)
  end

  context 'démarche non autorisée pour le token' do
    let(:other) { create(:procedure) }
    let(:variables) { { demarche: { number: other.id } } }

    it 'remonte une erreur' do
      expect(subject['errors']).to be_present
    end
  end
end
