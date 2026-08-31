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

    before do
      allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).and_return(nil)
    end

    context 'avec des paramètres valides' do
      before do
        allow(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, term, drop_down_other: nil)
          .and_return([
            { label: 'Papeete', value: '24:1', row_data: },
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

    it 'envoie data vide pour l\'option Autre (row_data nil)' do
      allow(ReferentielDePolynesie::API).to receive(:search_with_data)
        .and_return([{ label: I18n.t('shared.champs.drop_down_list.other'), value: Champs::DropDownListChamp::OTHER }])
      subject
      expect(response.parsed_body.first['data']).to eq('')
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

    context 'sur une table « Dites-le-nous une fois »' do
      let(:dlnuf) { { field_id: 9, field_name: 'Email', field_type: 'email' } }
      let(:dossier) { create(:dossier, user:) }

      before do
        allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with(domain_id).and_return(dlnuf)
      end

      it 'accepte q vide et scope la recherche sur le mail du titulaire' do
        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, nil, drop_down_other: nil, scope: { field_id: 9, value: user.email.downcase })
          .and_return([{ label: 'Ma ligne', value: '24:1', row_data: }])

        get :search, params: { table: domain_id, dossier_id: dossier.id }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.first['label']).to eq('Ma ligne')
      end

      it 'scope sur le mail du TITULAIRE quand un invité cherche' do
        invite_user = create(:user)
        create(:invite, dossier:, user: invite_user, email: invite_user.email)
        sign_in(invite_user)

        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, nil, drop_down_other: nil, scope: { field_id: 9, value: user.email.downcase })
          .and_return([])

        get :search, params: { table: domain_id, dossier_id: dossier.id }
        expect(response).to have_http_status(:ok)
      end

      it 'refuse (403) le dossier d\'un autre usager' do
        autre_dossier = create(:dossier)
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)

        get :search, params: { table: domain_id, dossier_id: autre_dossier.id, q: 'x' }
        expect(response).to have_http_status(:forbidden)
      end

      it 'refuse (403) sans dossier_id — jamais de repli en catalogue ouvert' do
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)

        get :search, params: { table: domain_id, q: 'x' }
        expect(response).to have_http_status(:forbidden)
      end

      it 'q libre ne désactive jamais le scope' do
        expect(ReferentielDePolynesie::API).to receive(:search_with_data)
          .with(domain_id, 'injection', drop_down_other: nil, scope: { field_id: 9, value: user.email.downcase })
          .and_return([])

        get :search, params: { table: domain_id, dossier_id: dossier.id, q: 'injection' }
        expect(response).to have_http_status(:ok)
      end

      it 'retourne [] si le dossier n\'a pas de titulaire avec mail (fail-closed silencieux)' do
        # pf: forcer la création du dossier AVANT le stub — sinon la validation de présence
        # de `belongs_to :user` échoue à la création puisqu'elle relit `user` (stubbé nil).
        dossier_id = dossier.id
        allow_any_instance_of(Dossier).to receive(:user).and_return(nil)
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)

        get :search, params: { table: domain_id, dossier_id: }
        expect(response.parsed_body).to eq([])
      end
    end

    context 'quand la config DLNUF est invalide (champ propriétaire mort)' do
      before do
        allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with(domain_id).and_return(:invalid)
      end

      it 'refuse d\'exposer (422) et alerte Sentry, sans appeler la recherche' do
        expect(Sentry).to receive(:capture_message).with(/champ propriétaire invalide/, anything)
        expect(ReferentielDePolynesie::API).not_to receive(:search_with_data)

        get :search, params: { table: domain_id, q: term }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['message']).to eq('Configuration du référentiel invalide')
      end
    end
  end
end
