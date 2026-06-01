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
      expect(data[:demarcheAjouterChamp][:champStableId]).to be_present
      libelles = procedure.draft_revision.reload.types_de_champ.map(&:libelle)
      expect(libelles).to include('Courriel')
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
