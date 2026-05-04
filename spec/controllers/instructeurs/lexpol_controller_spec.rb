# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Champs::LexpolController, type: :controller do
  render_views

  let(:instructeur) { create(:instructeur) }
  let(:procedure) { create(:procedure, :published, types_de_champ_public: [{ type: :lexpol }], instructeurs: [instructeur]) }
  let(:tdc) { procedure.active_revision.types_de_champ.first }
  let(:dossier) { create(:dossier, procedure:) }

  let(:value) { nil }
  let(:champ) { dossier.champ_for_update(tdc, row_id: nil, updated_by: instructeur).tap { |c| c.value = value }.tap(&:save!) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('LEXPOL_EMAIL').and_return('fake_email@example.com')
    allow(ENV).to receive(:fetch).with('LEXPOL_PASSWORD').and_return('fake_password')
    allow(ENV).to receive(:fetch).with('LEXPOL_AGENT_EMAIL').and_return('fake_agent_email@example.com')
    sign_in instructeur.user
  end

  describe 'POST #upsert' do
    context 'when dossier creation is successful' do
      before do
        allow_any_instance_of(LexpolService).to receive(:upsert_dossier).and_return('NOR-12345')

        post :upsert, params: {
          dossier_id: dossier.id,
          stable_id: champ.stable_id,
        }
      end

      it 'redirects to annotations page with success message for creation' do
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Dossier Lexpol créé avec succès')
      end
    end

    context 'when dossier update is successful' do
      let(:value) { 'NOR-12345' }
      before do
        allow_any_instance_of(LexpolService).to receive(:upsert_dossier).and_return(value)

        post :upsert, params: {
          dossier_id: dossier.id,
          stable_id: champ.stable_id,
        }
      end

      it 'redirects to annotations page with success message for update' do
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq('Dossier Lexpol mis à jour avec succès')
      end
    end

    context 'when dossier creation fails' do
      before do
        allow_any_instance_of(LexpolService).to receive(:upsert_dossier).and_raise(StandardError.new("test"))

        post :upsert, params: {
          dossier_id: dossier.id,
          stable_id: champ.stable_id,
        }
      end

      it 'redirects to annotations page with error message for creation' do
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Impossible de créer le dossier Lexpol')
        expect(flash[:alert]).to include('test')
      end
    end

    context 'when dossier update fails' do
      let(:value) { 'NOR-12345' }
      before do
        champ
        allow_any_instance_of(LexpolService).to receive(:upsert_dossier).and_raise(StandardError.new("test"))

        post :upsert, params: {
          dossier_id: dossier.id,
          stable_id: champ.stable_id,
        }
      end

      it 'redirects to annotations page with error message for update' do
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Impossible de mettre à jour le dossier Lexpol')
        expect(flash[:alert]).to include('test')
      end
    end

    context 'when access is denied (LexpolAccessDenied)' do
      before do
        allow_any_instance_of(LexpolService).to receive(:upsert_dossier).and_raise(
          APILexpol::LexpolAccessDenied.new("instructeur@example.com", 401)
        )
      end

      context 'for a regular instructeur' do
        before do
          post :upsert, params: {
            dossier_id: dossier.id,
            stable_id: champ.stable_id,
          }
        end

        it 'shows access denied error with email' do
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to include('Accès refusé à Lexpol avec le compte : instructeur@example.com')
        end
      end

      context 'for a super-admin with fallback' do
        let(:super_admin) { create(:super_admin) }

        before do
          sign_in super_admin
          allow(controller).to receive(:super_admin_signed_in?).and_return(true)

          # First call fails, second call (fallback) succeeds
          call_count = 0
          allow_any_instance_of(LexpolService).to receive(:upsert_dossier) do
            call_count += 1
            if call_count == 1
              raise APILexpol::LexpolAccessDenied.new("admin@example.com", 401)
            else
              'NOR-FALLBACK'
            end
          end

          post :upsert, params: {
            dossier_id: dossier.id,
            stable_id: champ.stable_id,
          }
        end

        it 'successfully creates dossier with service account' do
          expect(response).to redirect_to(root_path)
          expect(flash[:notice]).to include('compte de service')
        end
      end

      context 'for a super-admin when fallback also fails' do
        let(:super_admin) { create(:super_admin) }

        before do
          sign_in super_admin
          allow(controller).to receive(:super_admin_signed_in?).and_return(true)

          # Both calls fail - first with admin email, second with service email
          call_count = 0
          allow_any_instance_of(LexpolService).to receive(:upsert_dossier) do
            call_count += 1
            if call_count == 1
              raise APILexpol::LexpolAccessDenied.new("admin@example.com", 401)
            else
              raise APILexpol::LexpolAccessDenied.new("service@example.com", 401)
            end
          end

          post :upsert, params: {
            dossier_id: dossier.id,
            stable_id: champ.stable_id,
          }
        end

        it 'shows error for both accounts' do
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to include('Votre compte')
          expect(flash[:alert]).to include('compte de service')
          expect(flash[:alert]).to include('admin@example.com')
          expect(flash[:alert]).to include('service@example.com')
        end
      end
    end

    context 'with service account for draft revision' do
      let(:draft_procedure) { create(:procedure, types_de_champ_public: [{ type: :lexpol }], instructeurs: [instructeur]) }
      let(:draft_dossier) { create(:dossier, procedure: draft_procedure) }
      let(:draft_tdc) { draft_procedure.draft_revision.types_de_champ.first }
      let(:draft_champ) { draft_dossier.champ_for_update(draft_tdc, row_id: nil, updated_by: instructeur).tap(&:save!) }

      before do
        allow_any_instance_of(LexpolService).to receive(:upsert_dossier).and_return('NOR-TEST')

        post :upsert, params: {
          dossier_id: draft_dossier.id,
          stable_id: draft_champ.stable_id,
        }
      end

      it 'indicates service account was used' do
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to include('compte de service')
      end
    end

    context 'when required parameters are missing' do
      it 'raises an error for missing dossier_id' do
        expect {
          post :upsert, params: { champ_id: champ.id }
        }.to raise_error(ActionController::UrlGenerationError)
      end

      it 'raises an error for missing champ_id' do
        expect {
          post :upsert, params: { dossier_id: dossier.id }
        }.to raise_error(ActionController::UrlGenerationError)
      end
    end
  end

  describe 'GET #preview_variables' do
    def json_response
      response.parsed_body['grouped_variables']
    end

    before do
      procedure.draft_revision.add_type_de_champ(create(:type_de_champ_text, libelle: 'Nom', procedure: procedure))
      procedure.draft_revision.add_type_de_champ(create(:type_de_champ_piece_justificative, libelle: 'Document', procedure: procedure))
      dossier.reload
      dossier.champs.find { |c| c.libelle == 'Nom' }.update(value: 'Dupont')

      get :preview_variables, params: { dossier_id: dossier.id, stable_id: champ.stable_id }, format: :json
    end

    it 'retourne les 3 sections' do
      expect(json_response.keys).to match_array(['metadonnees', 'champs_formulaire', 'dossiers_lies'])
    end

    it 'inclut les champs remplis et exclut les types sans valeur' do
      expect(json_response['champs_formulaire']).to include('Nom' => 'Dupont')
      expect(json_response['champs_formulaire']).not_to have_key('Document')
    end

    context 'avec dossiers liés' do
      let(:accessible_procedure) { create(:procedure, :published, instructeurs: [instructeur]) }
      let(:accessible_dossier) { create(:dossier, procedure: accessible_procedure, user: dossier.user) }
      let(:inaccessible_procedure) { create(:procedure, :published, instructeurs: [create(:instructeur)]) }
      let(:inaccessible_dossier) { create(:dossier, procedure: inaccessible_procedure, user: create(:user)) }

      before do
        link_tdc = create(:type_de_champ_dossier_link, libelle: 'OK', procedure: procedure)
        link_tdc2 = create(:type_de_champ_dossier_link, libelle: 'KO', procedure: procedure)
        procedure.draft_revision.add_type_de_champ(link_tdc)
        procedure.draft_revision.add_type_de_champ(link_tdc2)
        dossier.reload
        dossier.project_champs_public_all.find { |c| c.libelle == 'OK' }.update(value: accessible_dossier.id.to_s)
        dossier.project_champs_public_all.find { |c| c.libelle == 'KO' }.update(value: inaccessible_dossier.id.to_s)

        get :preview_variables, params: { dossier_id: dossier.id, stable_id: champ.stable_id }, format: :json
      end

      it 'filtre selon les droits d\'accès' do
        expect(json_response['dossiers_lies'].keys.any? { |k| k.include?('OK') }).to be true
        # Le dossier KO doit avoir un message d'erreur
        ko_key = json_response['dossiers_lies'].keys.find { |k| k.include?('KO') }
        expect(json_response['dossiers_lies'][ko_key]).to eq('⚠️ Dossier lié non accessible')
      end
    end
  end
end
