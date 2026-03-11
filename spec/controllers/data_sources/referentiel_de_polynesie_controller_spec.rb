# frozen_string_literal: true

require 'rails_helper'

describe DataSources::ReferentielDePolynesieController, type: :controller do
  let(:user) { create(:user) }
  let(:domain_id) { '24' }
  let(:term) { 'Papeete' }
  let(:row_data) { { 'Nom' => 'Papeete', 'Code' => '98714', 'Ile' => 'Tahiti' } }

  before { sign_in(user) }

  # La route est : GET data_sources/referentiel_de_polynesie/:table/search?q=...
  # Le paramètre :table est dans l'URL, :q est un query param
  describe 'GET #search' do
    subject { get :search, params: { table: domain_id, q: term } }

    context 'avec des paramètres valides' do
      before do
        allow(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, term, drop_down_other: nil)
          .and_return([
            { label: 'Papeete', value: '24:1', row_data: }
          ])
      end

      it 'retourne HTTP 200' do
        expect(subject).to have_http_status(:ok)
      end

      it 'retourne un tableau JSON avec label, value et data chiffré' do
        subject
        body = response.parsed_body
        expect(body).to be_an(Array)
        expect(body.size).to eq(1)
        expect(body.first['label']).to eq('Papeete')
        expect(body.first['value']).to eq('24:1')
        expect(body.first['data']).to be_a(String)
        expect(body.first['data']).to be_present
      end

      it 'le blob data se déchiffre vers les données de la ligne' do
        subject
        encrypted_blob = response.parsed_body.first['data']
        decrypted = MessageEncryptorService.new.decrypt_and_verify(encrypted_blob, purpose: :storage)
        expect(JSON.parse(decrypted)).to eq(row_data)
      end

      it 'ne renvoie pas row_data en clair dans la réponse' do
        subject
        body = response.parsed_body.first
        expect(body.keys).to contain_exactly('label', 'value', 'data')
        expect(body).not_to have_key('row_data')
      end
    end

    context 'avec le paramètre drop_down_other' do
      subject { get :search, params: { table: domain_id, q: term, drop_down_other: 'true' } }

      it 'transmet drop_down_other à l\'API' do
        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, term, drop_down_other: true)
          .and_return([{ label: 'Papeete', value: '24:1', row_data: }])
        subject
      end
    end

    context 'quand le paramètre q est absent' do
      subject { get :search, params: { table: domain_id } }

      it 'retourne HTTP 400' do
        expect(subject).to have_http_status(400)
      end

      it 'retourne un message d\'erreur JSON' do
        subject
        expect(response.parsed_body['message']).to be_present
      end
    end

    context 'quand l\'API Baserow retourne un tableau vide' do
      before do
        allow(ReferentielDePolynesie::API).to receive(:search_with_data)
          .and_return([])
      end

      it 'retourne un tableau JSON vide' do
        subject
        expect(response.parsed_body).to eq([])
      end
    end

    context 'sans utilisateur connecté' do
      before { sign_out(user) }

      it 'redirige vers la page de connexion' do
        subject
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end
