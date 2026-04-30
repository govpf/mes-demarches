# frozen_string_literal: true

describe Instructeurs::DossierLayoutController, type: :controller do
  let(:instructeur) { create(:instructeur) }

  before { sign_in(instructeur.user) }

  describe 'POST #update' do
    context 'avec mode=grid' do
      it 'persiste la pref en DB' do
        post :update, params: { mode: 'grid' }

        expect(instructeur.reload.dossier_layout_preference).to eq('grid')
        expect(cookies[InstructeurChampDisplayHelper::DISMISSED_COOKIE.to_s]).to be_blank
      end
    end

    context 'avec mode=stacked' do
      it 'persiste la pref en DB' do
        post :update, params: { mode: 'stacked' }

        expect(instructeur.reload.dossier_layout_preference).to eq('stacked')
        expect(cookies[InstructeurChampDisplayHelper::DISMISSED_COOKIE.to_s]).to be_blank
      end
    end

    context 'avec mode=dismissed' do
      it 'pose uniquement le cookie de dismiss, sans toucher à la DB' do
        post :update, params: { mode: 'dismissed' }

        expect(cookies[InstructeurChampDisplayHelper::DISMISSED_COOKIE.to_s]).to be_present
        expect(instructeur.reload.dossier_layout_preference).to be_nil
      end
    end

    context 'avec un format JSON' do
      it 'répond en 204 No Content (pour le Stimulus controller)' do
        post :update, params: { mode: 'grid' }, format: :json

        expect(response).to have_http_status(:no_content)
      end
    end
  end

  describe 'routing' do
    it 'accepte grid, stacked, dismissed' do
      expect(post: '/dossier_layout/grid').to be_routable
      expect(post: '/dossier_layout/stacked').to be_routable
      expect(post: '/dossier_layout/dismissed').to be_routable
    end

    it 'refuse les autres valeurs' do
      expect(post: '/dossier_layout/foo').not_to be_routable
    end
  end
end
