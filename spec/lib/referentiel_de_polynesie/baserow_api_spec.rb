# frozen_string_literal: true

require 'rails_helper'

describe ReferentielDePolynesie::BaserowAPI do
  let(:domain_id) { '24' }
  let(:table_id) { '42' }
  let(:search_field_id) { 5 }
  let(:token) { 'test-token-abc' }
  let(:base_url) { 'https://baserow.example.com' }

  let(:config_response) do
    {
      'Table' => table_id,
      'Champ de recherche' => search_field_id,
      'Token' => token
    }
  end

  let(:fields_response) do
    [
      { 'id' => search_field_id, 'name' => 'Nom', 'type' => 'text' },
      { 'id' => 6, 'name' => 'Code', 'type' => 'text' },
      { 'id' => 7, 'name' => 'Ile', 'type' => 'text' }
    ]
  end

  before do
    ENV['API_BASEROW_URL'] = base_url
    ENV['API_BASEROW_TOKEN'] = 'config-token'
    ENV['API_BASEROW_CONFIG_TABLE'] = '1'
  end

  after do
    ENV.delete('API_BASEROW_URL')
    ENV.delete('API_BASEROW_TOKEN')
    ENV.delete('API_BASEROW_CONFIG_TABLE')
  end

  describe '.search_with_data' do
    let(:term) { 'Pape' }

    # Sans user_field_names=true, Baserow retourne des clés field_ID (ex: field_5, field_6)
    let(:baserow_results) do
      {
        results: [
          { id: 1, order: '1.00', field_5: 'Papeete', field_6: '98714', field_7: 'Tahiti' },
          { id: 2, order: '2.00', field_5: 'Papenoo', field_6: '98709', field_7: 'Tahiti' }
        ]
      }
    end

    before do
      stub_config = instance_double(Typhoeus::Response, success?: true, body: config_response.to_json)
      allow(Typhoeus).to receive(:get)
        .with("#{base_url}/api/database/rows/table/1/#{domain_id}/", anything)
        .and_return(stub_config)

      stub_fields = instance_double(Typhoeus::Response, success?: true, body: fields_response.to_json)
      allow(Typhoeus).to receive(:get)
        .with("#{base_url}/api/database/fields/table/#{table_id}/", anything)
        .and_return(stub_fields)

      stub_rows = instance_double(Typhoeus::Response, success?: true, body: baserow_results.to_json)
      allow(Typhoeus).to receive(:get)
        .with("#{base_url}/api/database/rows/table/#{table_id}/", anything)
        .and_return(stub_rows)
    end

    it 'retourne un tableau avec label, value et row_data' do
      results = described_class.search_with_data(domain_id, term)
      expect(results).to be_an(Array)
      expect(results.size).to eq(2)
    end

    it 'extrait le label depuis le champ de recherche via son ID (field_ID)' do
      results = described_class.search_with_data(domain_id, term)
      expect(results.first[:label]).to eq('Papeete')
      expect(results.second[:label]).to eq('Papenoo')
    end

    it 'construit value au format domain_id:row_id' do
      results = described_class.search_with_data(domain_id, term)
      expect(results.first[:value]).to eq("#{domain_id}:1")
      expect(results.second[:value]).to eq("#{domain_id}:2")
    end

    it 'retourne row_data avec les noms de champs (pas les IDs) comme clés' do
      results = described_class.search_with_data(domain_id, term)
      row = results.first[:row_data]
      expect(row).to be_a(Hash)
      expect(row).not_to have_key('id')
      expect(row).not_to have_key('order')
      expect(row).not_to have_key('field_5')
      expect(row['Nom']).to eq('Papeete')
      expect(row['Code']).to eq('98714')
      expect(row['Ile']).to eq('Tahiti')
    end

    it 'ne passe pas user_field_names=true dans la requête de recherche (compatibilité filtres)' do
      expect(Typhoeus).to receive(:get)
        .with("#{base_url}/api/database/rows/table/#{table_id}/", hash_including(params: hash_not_including(user_field_names: true)))
        .and_return(instance_double(Typhoeus::Response, success?: true, body: baserow_results.to_json))
        .once

      # override le stub générique pour vérifier les params spécifiquement
      allow(Typhoeus).to receive(:get)
        .with("#{base_url}/api/database/rows/table/#{table_id}/", anything)
        .and_return(instance_double(Typhoeus::Response, success?: true, body: baserow_results.to_json))

      described_class.search_with_data(domain_id, term)
    end

    context 'avec des valeurs Baserow complexes (single_select, symbolisées)' do
      let(:baserow_results) do
        {
          results: [
            {
              id: 1, order: '1.00',
              field_5: 'Papeete',
              # single_select symbolisé (résultat de symbolize_names: true sur JSON.parse)
              field_6: { id: 3, value: 'Îles du Vent', color: 'red' },
              field_7: [{ id: 1, value: 'Capitale' }, { id: 2, value: 'Principal' }]
            }
          ]
        }
      end

      it 'simplifie les valeurs single_select (clés symbolisées)' do
        results = described_class.search_with_data(domain_id, term)
        expect(results.first[:row_data]['Code']).to eq('Îles du Vent')
      end

      it 'simplifie les valeurs multiple_select en chaîne (clés symbolisées)' do
        results = described_class.search_with_data(domain_id, term)
        expect(results.first[:row_data]['Ile']).to eq('Capitale, Principal')
      end
    end

    context 'quand config retourne nil (domaine inconnu)' do
      before do
        stub_not_found = instance_double(Typhoeus::Response, success?: false, body: '')
        allow(Typhoeus).to receive(:get)
          .with("#{base_url}/api/database/rows/table/1/#{domain_id}/", anything)
          .and_return(stub_not_found)
      end

      it 'retourne un tableau vide' do
        expect(described_class.search_with_data(domain_id, term)).to eq([])
      end
    end

    context 'quand la requête Baserow retourne 400 (comme avec user_field_names + filtres ID)' do
      before do
        stub_error = instance_double(Typhoeus::Response, success?: false, body: 'Bad Request')
        allow(Typhoeus).to receive(:get)
          .with("#{base_url}/api/database/rows/table/#{table_id}/", anything)
          .and_return(stub_error)
      end

      it 'retourne un tableau vide (pas d\'erreur levée)' do
        expect(described_class.search_with_data(domain_id, term)).to eq([])
      end
    end

    context 'avec drop_down_other: true' do
      it 'ajoute l\'option "Autre" à la fin des résultats' do
        results = described_class.search_with_data(domain_id, term, drop_down_other: true)
        last = results.last
        expect(last[:value]).to eq(Champs::DropDownListChamp::OTHER)
        expect(last[:label]).to eq(I18n.t('shared.champs.drop_down_list.other'))
      end
    end
  end
end
