# frozen_string_literal: true

RSpec.describe 'Polynesian Fields GraphQL', type: :graphql do
  let(:context) { { internal_use: true } }
  let(:variables) { { number: dossier.id } }
  let(:procedure) do
    create(:procedure, :published, types_de_champ_public: [
      { type: :nationalites, libelle: 'Nationalité' },
      { type: :commune_de_polynesie, libelle: 'Commune de Polynésie' },
      { type: :code_postal_de_polynesie, libelle: 'Code postal de Polynésie' },
      { type: :numero_dn, libelle: 'Numéro DN' },
      { type: :te_fenua, libelle: 'Carte TeFenua' },
    ])
  end
  let(:dossier) { create(:dossier, :accepte, :with_populated_champs, procedure: procedure) }

  subject { API::V2::Schema.execute(query, variables: variables, context: context) }

  let(:data) { subject['data'].deep_symbolize_keys }
  let(:errors) { subject['errors'] }

  before do
    populate_polynesian_fields
  end

  describe 'dossier with Polynesian fields' do
    let(:query) { POLYNESIAN_FIELDS_QUERY }

    context 'Text-based Polynesian fields' do
      it 'returns correct data for nationalités field' do
        expect(errors).to be_nil

        nationalites_champ = data[:dossier][:champs].find { |c| c[:label] == 'Nationalité' }
        expect(nationalites_champ[:__typename]).to eq('TextChamp')
        expect(nationalites_champ[:stringValue]).to eq('Australienne')
      end

      it 'returns correct data for commune de polynésie field' do
        expect(errors).to be_nil

        commune_champ = data[:dossier][:champs].find { |c| c[:label] == 'Commune de Polynésie' }
        expect(commune_champ[:__typename]).to eq('TextChamp')
        expect(commune_champ[:stringValue]).to include('Mahina')
      end

      it 'returns correct data for code postal de polynésie field' do
        expect(errors).to be_nil

        code_postal_champ = data[:dossier][:champs].find { |c| c[:label] == 'Code postal de Polynésie' }
        expect(code_postal_champ[:__typename]).to eq('TextChamp')
        expect(code_postal_champ[:stringValue]).to include('98709')
      end
    end

    context 'Specialized Polynesian fields' do
      it 'returns correct data for numero DN field' do
        expect(errors).to be_nil

        numero_dn_champ = data[:dossier][:champs].find { |c| c[:__typename] == 'NumeroDnChamp' }
        expect(numero_dn_champ).not_to be_nil
        expect(numero_dn_champ[:label]).to eq('Numéro DN')
        expect(numero_dn_champ[:numeroDn]).to eq('2106223')
        expect(numero_dn_champ[:dateDeNaissance]).to eq('1983-11-28')
      end

      it 'returns correct data for TeFenua field' do
        expect(errors).to be_nil

        te_fenua_champ = data[:dossier][:champs].find { |c| c[:__typename] == 'TeFenuaChamp' }
        expect(te_fenua_champ).not_to be_nil
        expect(te_fenua_champ[:label]).to eq('Carte TeFenua')
        expect(te_fenua_champ[:geoAreas]).to be_an(Array)
      end
    end
  end

  private

  def populate_polynesian_fields
    champs = dossier.project_champs_public

    # Remplir les champs avec des données de test valides
    champs.find { _1.type_champ == 'nationalites' }&.update(value: 'Australienne')
    champs.find { _1.type_champ == 'commune_de_polynesie' }&.update(value: 'Mahina - Tahiti - 98709')
    champs.find { _1.type_champ == 'code_postal_de_polynesie' }&.update(value: '98709 - Mahina - Tahiti')

    numero_dn_champ = champs.find { _1.type_champ == 'numero_dn' }
    if numero_dn_champ
      numero_dn_champ.update(
        numero_dn: '2106223',
        date_de_naissance: '1983-11-28'
      )
    end
  end

  POLYNESIAN_FIELDS_QUERY = <<-GRAPHQL
    query($number: Int!) {
      dossier(number: $number) {
        id
        number
        champs {
          id
          label
          __typename
          stringValue
          ... on NumeroDnChamp {
            numeroDn
            dateDeNaissance
          }
          ... on TeFenuaChamp {
            geoAreas {
              id
              source
            }
          }
        }
      }
    }
  GRAPHQL
end
