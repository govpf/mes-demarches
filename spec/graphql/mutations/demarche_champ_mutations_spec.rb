# frozen_string_literal: true

RSpec.describe 'Mutations MCP construction de champs', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:procedure) { create(:procedure, administrateurs: [admin], types_de_champ_public: [{ type: :text, libelle: 'Nom' }]) }
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: true } }
  let(:variables) { {} }

  subject { API::V2::Schema.execute(query, variables:, context:) }

  let(:data) { subject['data'].deep_symbolize_keys }

  describe 'demarcheAjouterChamp' do
    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheAjouterChampInput!) {
        demarcheAjouterChamp(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end
    let(:variables) do
      { input: { demarche: { number: procedure.id }, typeChamp: 'email', libelle: 'Courriel' } }
    end

    it 'ajoute le champ au brouillon' do
      expect(data[:demarcheAjouterChamp][:errors]).to be_nil
      new_tdc = procedure.draft_revision.reload.types_de_champ.find { _1.libelle == 'Courriel' }
      expect(new_tdc).to be_present
      expect(data[:demarcheAjouterChamp][:champStableId]).to eq(new_tdc.stable_id.to_s)
    end

    context 'insertion dans une répétition via parent_stable_id' do
      let(:procedure) do
        create(:procedure, administrateurs: [admin],
          types_de_champ_public: [{ type: :repetition, libelle: 'Lignes', children: [{ type: :text, libelle: 'Existant' }] }])
      end
      let(:repetition_stable_id) { procedure.draft_revision.types_de_champ.find { _1.libelle == 'Lignes' }.stable_id.to_s }
      let(:variables) do
        { input: { demarche: { number: procedure.id }, typeChamp: 'text', libelle: 'Quantité', parentStableId: repetition_stable_id } }
      end

      it 'insère le champ enfant dans la répétition' do
        expect(data[:demarcheAjouterChamp][:errors]).to be_nil
        new_tdc = procedure.draft_revision.reload.types_de_champ.find { _1.libelle == 'Quantité' }
        expect(new_tdc).to be_present
        coordinate = procedure.draft_revision.revision_types_de_champ.find { _1.stable_id == new_tdc.stable_id }
        expect(coordinate.child?).to be(true)
      end
    end

    context 'type inconnu' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, typeChamp: 'pas_un_type', libelle: 'X' } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheAjouterChamp][:champStableId]).to be_nil
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include('Type de champ inconnu')
      end
    end

    context 'démarche non autorisée pour le token' do
      let(:other_procedure) { create(:procedure) }
      let(:variables) do
        { input: { demarche: { number: other_procedure.id }, typeChamp: 'text', libelle: 'X' } }
      end

      it 'retourne une erreur d autorisation' do
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include('accès')
      end
    end

    context 'token en lecture seule' do
      let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }

      it 'refuse la mutation' do
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include('lecture')
      end
    end
  end
end
