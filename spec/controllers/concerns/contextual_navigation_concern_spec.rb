# pf: tests pour la navigation contextuelle entre personas
RSpec.describe ContextualNavigationConcern, type: :controller do
  controller(ApplicationController) do
    include ContextualNavigationConcern
    
    def index
      render plain: 'test'
    end
  end

  let(:user) { create(:user) }
  let(:instructeur) { create(:instructeur) }
  let(:administrateur) { create(:administrateur) }
  let(:procedure) { create(:procedure, :published, administrateurs: [administrateur]) }
  let(:dossier) { create(:dossier, procedure: procedure, user: user) }

  before do
    routes.draw { get 'index' => 'anonymous#index' }
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:user_signed_in?).and_return(true)
    allow(controller).to receive(:instructeur_signed_in?).and_return(false)
    allow(controller).to receive(:administrateur_signed_in?).and_return(false)
  end

  describe '#contextual_persona_enabled?' do
    context 'when no user is signed in' do
      before { allow(controller).to receive(:current_user).and_return(nil) }
      
      it 'returns false' do
        expect(controller.send(:contextual_persona_enabled?)).to be false
      end
    end

    context 'when user is signed in but feature is disabled' do
      before { Flipper.disable(:contextual_persona_navigation, user) }
      
      it 'returns false' do
        expect(controller.send(:contextual_persona_enabled?)).to be false
      end
    end

    context 'when user is signed in and feature is enabled' do
      before { Flipper.enable(:contextual_persona_navigation, user) }
      
      it 'returns true' do
        expect(controller.send(:contextual_persona_enabled?)).to be true
      end
    end
  end

  describe '#contextual_redirect_path_for_profile' do
    before { Flipper.enable(:contextual_persona_navigation, user) }

    context 'when feature is disabled' do
      before { Flipper.disable(:contextual_persona_navigation, user) }
      
      it 'returns nil' do
        expect(controller.send(:contextual_redirect_path_for_profile, :instructeur)).to be_nil
      end
    end

    context 'when no context is available' do
      before do
        allow(controller).to receive(:current_context_info).and_return({})
      end
      
      it 'returns nil' do
        expect(controller.send(:contextual_redirect_path_for_profile, :instructeur)).to be_nil
      end
    end

    context 'when switching to instructeur' do
      before do
        allow(controller).to receive(:current_context_info).and_return({ type: :dossier, id: dossier.id })
        allow(controller).to receive(:instructeur_signed_in?).and_return(true)
        allow(controller).to receive(:current_instructeur).and_return(instructeur)
        instructeur.procedures << procedure
      end
      
      it 'returns instructeur dossier path when user can access dossier as instructeur' do
        expected_path = "/instructeurs/procedures/#{procedure.id}/dossiers/#{dossier.id}"
        allow(controller).to receive(:instructeur_dossier_path).with(procedure_id: procedure.id, dossier_id: dossier.id).and_return(expected_path)
        
        result = controller.send(:contextual_redirect_path_for_profile, :instructeur)
        expect(result).to eq(expected_path)
      end

      it 'returns nil when user cannot access dossier as instructeur' do
        instructeur.procedures.clear
        
        result = controller.send(:contextual_redirect_path_for_profile, :instructeur)
        expect(result).to be_nil
      end
    end

    context 'when switching to user' do
      before do
        allow(controller).to receive(:current_context_info).and_return({ type: :dossier, id: dossier.id })
      end
      
      it 'returns user dossier path when user can access dossier' do
        expected_path = "/dossiers/#{dossier.id}"
        allow(controller).to receive(:dossier_path).with(dossier.id).and_return(expected_path)
        
        result = controller.send(:contextual_redirect_path_for_profile, :user)
        expect(result).to eq(expected_path)
      end

      it 'returns nil when user cannot access dossier' do
        other_user = create(:user)
        other_dossier = create(:dossier, user: other_user)
        allow(controller).to receive(:current_context_info).and_return({ type: :dossier, id: other_dossier.id })
        
        result = controller.send(:contextual_redirect_path_for_profile, :user)
        expect(result).to be_nil
      end
    end

    context 'when switching to administrateur' do
      before do
        allow(controller).to receive(:current_context_info).and_return({ type: :procedure, id: procedure.id })
        allow(controller).to receive(:administrateur_signed_in?).and_return(true)
        allow(controller).to receive(:current_administrateur).and_return(administrateur)
      end
      
      it 'returns admin procedure path when user can access procedure as admin' do
        expected_path = "/admin/procedures/#{procedure.id}"
        allow(controller).to receive(:admin_procedure_path).with(procedure.id).and_return(expected_path)
        
        result = controller.send(:contextual_redirect_path_for_profile, :administrateur)
        expect(result).to eq(expected_path)
      end

      it 'returns nil when user cannot access procedure as admin' do
        other_admin = create(:administrateur)
        allow(controller).to receive(:current_administrateur).and_return(other_admin)
        
        result = controller.send(:contextual_redirect_path_for_profile, :administrateur)
        expect(result).to be_nil
      end
    end

    context 'when an error occurs' do
      before do
        allow(controller).to receive(:current_context_info).and_raise(StandardError, 'Test error')
        allow(Rails.logger).to receive(:error)
      end
      
      it 'logs the error and returns nil' do
        result = controller.send(:contextual_redirect_path_for_profile, :instructeur)
        
        expect(Rails.logger).to have_received(:error).with('[ContextualNav] Error: Test error')
        expect(result).to be_nil
      end
    end
  end

  describe '#current_context_info' do
    context 'when on users/dossiers controller' do
      before { allow(controller).to receive(:controller_path).and_return('users/dossiers') }
      
      it 'extracts dossier ID from params[:id]' do
        allow(controller).to receive(:params).and_return({ id: '123' })
        
        result = controller.send(:current_context_info)
        expect(result).to eq({ type: :dossier, id: '123' })
      end
    end

    context 'when on instructeurs/dossiers controller' do
      before { allow(controller).to receive(:controller_path).and_return('instructeurs/dossiers') }
      
      it 'extracts dossier ID from params[:dossier_id]' do
        allow(controller).to receive(:params).and_return({ dossier_id: '456' })
        
        result = controller.send(:current_context_info)
        expect(result).to eq({ type: :dossier, id: '456' })
      end
    end

    context 'when on instructeurs/procedures controller' do
      before { allow(controller).to receive(:controller_path).and_return('instructeurs/procedures') }
      
      context 'with dossier_id present' do
        it 'extracts dossier context' do
          allow(controller).to receive(:params).and_return({ dossier_id: '789', procedure_id: '101' })
          
          result = controller.send(:current_context_info)
          expect(result).to eq({ type: :dossier, id: '789' })
        end
      end

      context 'without dossier_id' do
        it 'extracts procedure context' do
          allow(controller).to receive(:params).and_return({ procedure_id: '101' })
          
          result = controller.send(:current_context_info)
          expect(result).to eq({ type: :procedure, id: '101' })
        end
      end
    end

    context 'when on administrateurs/procedures controller' do
      before { allow(controller).to receive(:controller_path).and_return('administrateurs/procedures') }
      
      it 'extracts procedure ID from params[:id]' do
        allow(controller).to receive(:params).and_return({ id: '202' })
        
        result = controller.send(:current_context_info)
        expect(result).to eq({ type: :procedure, id: '202' })
      end

      it 'extracts procedure ID from params[:procedure_id] as fallback' do
        allow(controller).to receive(:params).and_return({ procedure_id: '303' })
        
        result = controller.send(:current_context_info)
        expect(result).to eq({ type: :procedure, id: '303' })
      end
    end

    context 'when on unknown controller' do
      before { allow(controller).to receive(:controller_path).and_return('other/controller') }
      
      it 'returns empty hash' do
        result = controller.send(:current_context_info)
        expect(result).to eq({})
      end
    end
  end
end