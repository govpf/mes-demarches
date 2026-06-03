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
        position
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
    expect(champs.first[:position]).to eq(0)
    expect(champs.first[:parentStableId]).to be_nil
  end

  context 'démarche non autorisée pour le token' do
    let(:other) { create(:procedure) }
    let(:variables) { { demarche: { number: other.id } } }

    it 'remonte une erreur' do
      expect(subject['errors']).to be_present
    end
  end

  context 'champ enfant dans une répétition' do
    let(:procedure) do
      create(:procedure, administrateurs: [admin], types_de_champ_public: [
        { type: :repetition, libelle: 'Lignes', children: [{ type: :text, libelle: 'Ligne' }] },
      ])
    end

    it 'expose le parentStableId de l enfant' do
      champs = data[:demarcheChamps]
      repetition = champs.find { _1[:libelle] == 'Lignes' }
      enfant = champs.find { _1[:libelle] == 'Ligne' }
      expect(repetition).to be_present
      expect(enfant).to be_present
      expect(enfant[:parentStableId]).to eq(repetition[:stableId])
    end
  end
end
