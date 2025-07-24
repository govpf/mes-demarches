# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TeFenua GraphQL API', type: :graphql do
  let(:procedure) { create(:procedure, :published, types_de_champ_public: [{ type: :te_fenua, stable_id: 99 }]) }
  let(:dossier) { create(:dossier, :accepte, procedure: procedure) }
  let(:champ) { dossier.project_champs_public.first }
  let(:context) { { internal_use: true } }

  let(:query) do
    <<-GRAPHQL
    query($number: Int!) {
      dossier(number: $number) {
        champs {
          __typename
          ... on TeFenuaChamp {
            geoAreas {
              __typename
              source
              geometry { type }
              ... on Marqueur {
                commune
                ile
              }
              ... on Zone {
                commune
                ile
                surface
                surfaceCalculee
              }
              ... on ParcelleCadastrale {
                commune
                ile
                surface
                numero
                section
              }
              ... on Batiment {
                nom
                commune
                ile
                surface
              }
            }
          }
        }
      }
    }
    GRAPHQL
  end

  let(:variables) { { number: dossier.id } }

  describe 'with complete TeFenua data' do
    before do
      champ.update(value: {
        parcelles: {
          features: [
            {
              geometry: { type: 'Polygon', coordinates: [[[-149.5, -17.5], [-149.4, -17.5], [-149.4, -17.4], [-149.5, -17.4], [-149.5, -17.5]]] },
                        properties: { commune: 'Papeete', ile: 'Tahiti', surface: '1000', numero: '123', section: 'AB' }
            }
          ]
        },
        batiments: {
          features: [
            {
              geometry: { type: 'Polygon', coordinates: [[[-149.45, -17.45], [-149.44, -17.45], [-149.44, -17.44], [-149.45, -17.44], [-149.45, -17.45]]] },
                        properties: { nom: 'Maison', commune: 'Papeete', ile: 'Tahiti', surface: '150' }
            }
          ]
        },
        zones_manuelles: {
          features: [
            {
              geometry: { type: 'Polygon', coordinates: [[[-149.47, -17.47], [-149.46, -17.47], [-149.46, -17.46], [-149.47, -17.46], [-149.47, -17.47]]] },
              properties: { commune: 'Papeete', ile: 'Tahiti', surface: '500' }
            },
            {
              geometry: { type: 'Point', coordinates: [-149.48, -17.48] },
              properties: { commune: 'Papeete', ile: 'Tahiti' }
            }
          ]
        }
      }.to_json)
    end

    it 'returns correctly typed geo areas' do
      result = API::V2::Schema.execute(query, variables: variables, context: context)
      data = result.to_h.deep_symbolize_keys[:data]

      te_fenua_champ = data[:dossier][:champs].find { |c| c[:__typename] == 'TeFenuaChamp' }
      geo_areas = te_fenua_champ[:geoAreas]

      expect(geo_areas.size).to eq(4)

      parcelle = geo_areas.find { |area| area[:__typename] == 'ParcelleCadastrale' }
      expect(parcelle).to include(
        __typename: 'ParcelleCadastrale',
        source: 'cadastre',
        commune: 'Papeete',
        ile: 'Tahiti',
        surface: '1000',
        numero: '123',
        section: 'AB'
      )
      expect(parcelle[:geometry][:type]).to eq('Polygon')

      batiment = geo_areas.find { |area| area[:__typename] == 'Batiment' }
      expect(batiment).to include(
        __typename: 'Batiment',
        source: 'batiment',
        nom: 'Maison',
        commune: 'Papeete',
        ile: 'Tahiti',
        surface: '150'
      )

      zone = geo_areas.find { |area| area[:__typename] == 'Zone' }
      expect(zone).to include(
        __typename: 'Zone',
        source: 'selection_utilisateur',
        commune: 'Papeete',
        ile: 'Tahiti',
        surface: '500'
      )
      expect(zone[:surfaceCalculee]).to be_present

      marqueur = geo_areas.find { |area| area[:__typename] == 'Marqueur' }
      expect(marqueur).to include(
        __typename: 'Marqueur',
        source: 'selection_utilisateur',
        commune: 'Papeete',
        ile: 'Tahiti'
      )
      expect(marqueur[:geometry][:type]).to eq('Point')
    end
  end

  describe 'type resolution based on geometry' do
    it 'resolves polygon as Zone and point as Marqueur' do
      champ.update(value: {
        zones_manuelles: {
          features: [
            {
              geometry: { type: 'Polygon', coordinates: [[[-149.5, -17.5], [-149.4, -17.5], [-149.4, -17.4], [-149.5, -17.4], [-149.5, -17.5]]] },
              properties: { commune: 'Papeete', surface: '1000' }
            },
            {
              geometry: { type: 'Point', coordinates: [-149.5, -17.5] },
              properties: { commune: 'Papeete' }
            }
          ]
        }
      }.to_json)

      result = API::V2::Schema.execute(query, variables: variables, context: context)
      data = result.to_h.deep_symbolize_keys[:data]

      geo_areas = data[:dossier][:champs].first[:geoAreas]

      zone = geo_areas.find { |area| area[:__typename] == 'Zone' }
      expect(zone[:geometry][:type]).to eq('Polygon')
      expect(zone[:surface]).to eq('1000')

      marqueur = geo_areas.find { |area| area[:__typename] == 'Marqueur' }
      expect(marqueur[:geometry][:type]).to eq('Point')
    end
  end

  describe 'source attribution' do
    it 'assigns correct sources to different area types' do
      champ.update(value: {
        parcelles: { features: [{ geometry: { type: 'Polygon', coordinates: [[[-149.5, -17.5], [-149.4, -17.5], [-149.4, -17.4], [-149.5, -17.4], [-149.5, -17.5]]] }, properties: {} }] },
        batiments: { features: [{ geometry: { type: 'Point', coordinates: [-149.45, -17.45] }, properties: {} }] }
      }.to_json)

      result = API::V2::Schema.execute(query, variables: variables, context: context)
      data = result.to_h.deep_symbolize_keys[:data]

      geo_areas = data[:dossier][:champs].first[:geoAreas]

      parcelle = geo_areas.find { |area| area[:__typename] == 'ParcelleCadastrale' }
      expect(parcelle[:source]).to eq('cadastre')

      batiment = geo_areas.find { |area| area[:__typename] == 'Batiment' }
      expect(batiment[:source]).to eq('batiment')
    end
  end

  describe 'with empty data' do
    before { champ.update(value: '{}') }

    it 'returns empty geo areas array' do
      result = API::V2::Schema.execute(query, variables: variables, context: context)
      data = result.to_h.deep_symbolize_keys[:data]

      te_fenua_champ = data[:dossier][:champs].find { |c| c[:__typename] == 'TeFenuaChamp' }
      expect(te_fenua_champ[:geoAreas]).to eq([])
    end
  end
end
