# frozen_string_literal: true

describe OmniauthController, type: :controller do
  let(:birthdate) { '20150821' }
  let(:email) { 'EMAIL_from_fc@test.com' }
  let(:provider) { 'google' }

  let(:user_info) do
    {
      france_connect_particulier_id: 'blablabla',
      given_name: 'titi',
      family_name: 'toto',
      birthdate: birthdate,
      birthplace: '1234',
      gender: 'M',
      email_france_connect: email,
    }
  end

  describe '#auth' do
    subject { get :login, params: { provider: provider } }

    it { is_expected.to have_http_status(:redirect) }
  end

  describe '#callback' do
    let(:code) { 'plop' }
    let(:state) { 'valid-state' }

    # pf: sécurité (F2) — le state est validé contre la session ; on simule un login
    # antérieur ayant stocké le state.
    before { request.session[:omniauth_state] = 'valid-state' }

    subject { get :callback, params: { code: code, state: state, provider: provider } }

    context 'when params are missing' do
      subject { get :callback, params: { provider: provider } }

      it { is_expected.to redirect_to(new_user_session_path) }
    end

    context 'when the OAuth state is invalid (CSRF)' do
      let(:state) { 'forged-state' }

      it 'rejects and redirects to login without retrieving user informations' do
        expect(OmniAuthService).not_to receive(:find_or_retrieve_user_informations)
        expect(subject).to redirect_to(new_user_session_path)
      end
    end

    context 'when the OAuth state is missing from session' do
      before { request.session.delete(:omniauth_state) }

      it { is_expected.to redirect_to(new_user_session_path) }
    end

    context 'when param code is missing' do
      let(:code) { nil }

      it { is_expected.to redirect_to(new_user_session_path) }
    end

    context 'when param code is empty' do
      let(:code) { '' }

      it { is_expected.to redirect_to(new_user_session_path) }
    end

    context 'when code is correct' do
      before do
        allow(OmniAuthService).to receive(:retrieve_user_informations)
          .and_return(FranceConnectInformation.new(user_info))
      end

      context 'when france_connect_particulier_id exists in database' do
        let!(:fci) { FranceConnectInformation.create!(user_info.merge(user_id: fc_user&.id)) }

        context 'and is linked to an user' do
          let(:fc_user) { create(:user, email: 'associated_user@a.com') }

          it { expect { subject }.not_to change { FranceConnectInformation.count } }

          it 'signs in with the fci associated user' do
            subject
            expect(controller.current_user).to eq(fc_user)
            expect(fc_user.reload.loged_in_with_france_connect).to eq(User.loged_in_with_france_connects.fetch(provider))
          end

          context 'and the user has a stored location' do
            let(:stored_location) { '/plip/plop' }
            before { controller.store_location_for(:user, stored_location) }

            it { is_expected.to redirect_to(stored_location) }
          end
        end

        context 'and is linked an instructeur' do
          let(:fc_user) { create(:instructeur, email: 'another_email@a.com').user }

          before { subject }

          it do
            expect(response).to redirect_to(new_user_session_path)
            expect(flash[:alert]).to be_present
          end
        end

        context 'and is not linked to an user' do
          let(:fc_user) { nil }

          context 'and no user with the same email exists' do
            it 'renders choose_email template and does not create user yet' do
              expect { subject }.not_to change { User.count }
              expect(response).to render_template(:choose_email)
            end
          end

          context 'and an user with the same email exists' do
            let!(:preexisting_user) { create(:user, email: email) }

            context 'and the email assertion is NOT trusted (F4)' do
              it 'redirects to the merge process (requiert une preuve)' do
                expect { subject }.not_to change { User.count }

                expect(response).to redirect_to(omniauth_merge_path(provider, fci.reload.merge_token))
              end
            end

            context 'and the email assertion is trusted (F4)' do
              before do
                trusted_fci = FranceConnectInformation.new(user_info)
                trusted_fci.trusted_email_assertion = true
                allow(OmniAuthService).to receive(:retrieve_user_informations).and_return(trusted_fci)
              end

              it 'merges without password and signs in' do
                subject

                expect(controller.current_user).to eq(preexisting_user)
                expect(fci.reload.user).to eq(preexisting_user)
              end
            end
          end
          context 'and an instructeur with the same email exists' do
            let!(:preexisting_user) { create(:instructeur, email: email) }

            it 'redirects to the merge process' do
              expect { subject }.not_to change { User.count }

              expect(response).to redirect_to(new_user_session_path)
              expect(flash[:alert]).to eq(I18n.t('errors.messages.omniauth.forbidden_html', reset_link: new_user_password_path, provider: I18n.t("omniauth.provider.#{provider}")))
            end
          end
        end
      end

      context 'when france_connect_particulier_id does not exist in database' do
        it { expect { subject }.to change { FranceConnectInformation.count }.by(1) }

        describe 'FranceConnectInformation attributs' do
          let(:stored_fci) { FranceConnectInformation.last }

          before { subject }

          it { expect(stored_fci).to have_attributes(user_info.merge(birthdate: Time.zone.parse(birthdate).to_datetime)) }
        end

        it { is_expected.to render_template(:choose_email) }
      end
    end

    context 'when code is not correct' do
      before do
        allow(OmniAuthService).to receive(:retrieve_user_informations) { raise Rack::OAuth2::Client::Error.new(500, error: 'Unknown') }
        subject
      end

      it {
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to be_present
      }
    end
  end

  RSpec.shared_examples "a method that needs a valid merge token" do
    context 'when the merge token is invalid' do
      before do
        stub_const("APPLICATION_NAME", "demarches-simplifiees.fr")
        merge_token
        fci.update(merge_token_created_at: 2.years.ago)
      end

      it do
        if format == :js
          subject
          expect(response.body).to eq("window.location.href='/'")
        else
          expect(subject).to redirect_to root_path
        end
        expect(flash.alert).to eq('Le délai pour fusionner les comptes Google et demarches-simplifiees.fr est expiré. Veuillez recommencer la procédure pour fusionner les comptes.')
      end
    end
  end

  describe '#merge' do
    let(:fci) { FranceConnectInformation.create!(user_info) }
    let(:merge_token) { fci.create_merge_token! }
    let(:format) { :html }

    subject { get :merge, params: { provider: provider, merge_token: merge_token } }

    context 'when the merge token is valid' do
      it { expect(subject).to have_http_status(:ok) }
    end

    it_behaves_like "a method that needs a valid merge token"

    context 'when the merge token does not exist' do
      let(:merge_token) { 'i do not exist' }

      before do
        stub_const("APPLICATION_NAME", "demarches-simplifiees.fr")
      end

      it do
        expect(subject).to redirect_to root_path
        expect(flash.alert).to eq('Le délai pour fusionner les comptes Google et demarches-simplifiees.fr est expiré. Veuillez recommencer la procédure pour fusionner les comptes.')
      end
    end
  end

  describe '#merge_with_existing_account' do
    let(:fci) { FranceConnectInformation.create!(user_info) }
    let(:merge_token) { fci.create_merge_token! }
    let(:email) { 'EXISTING_account@a.com ' }
    let(:password) { SECURE_PASSWORD }
    let(:format) { :turbo_stream }

    subject { post :merge_with_existing_account, params: { merge_token:, email:, password:, provider: }, format: }

    it_behaves_like "a method that needs a valid merge token"

    context 'when the user is not found' do
      it 'does not log' do
        subject
        fci.reload

        expect(fci.user).to be_nil
        expect(fci.merge_token).not_to be_nil
        expect(controller.current_user).to be_nil
      end
    end

    context 'when the credentials are ok' do
      let!(:user) { create(:user, email: email, password: password) }

      it 'merges the account, signs in, and delete the merge token' do
        subject
        fci.reload

        expect(fci.user).to eq(user)
        expect(user.reload.email_verified_at).to be_present
        expect(fci.merge_token).to be_nil
        expect(controller.current_user).to eq(user)
      end

      context 'but the targeted user is an instructeur' do
        let!(:user) { create(:instructeur, email: email, password: password).user }

        it 'redirects to the root page' do
          subject

          expect { fci.reload }.to raise_error(ActiveRecord::RecordNotFound)

          expect(controller.current_user).to be_nil
        end
      end
    end

    context 'when the credentials are not ok' do
      let!(:user) { create(:user, email: email, password: 'another password #$21$%%') }

      it 'increases the failed attempts counter' do
        subject
        fci.reload

        expect(fci.user).to be_nil
        expect(fci.merge_token).not_to be_nil
        expect(controller.current_user).to be_nil
        expect(user.reload.failed_attempts).to eq(1)
      end
    end
  end

  # pf: la fusion d'une identité provider dans un compte existant exige une preuve
  # du titulaire du compte (mot de passe, ou lien reçu à l'adresse du compte).
  describe 'merge into an existing account without proof' do
    include ActiveJob::TestHelper

    let(:fci) { FranceConnectInformation.create!(user_info) }
    let(:merge_token) { fci.create_merge_token! }
    let!(:account) { create(:user, email: 'account@a.com') }

    def merge_links_sent_to(address)
      ActionMailer::Base.deliveries
        .filter { |mail| mail.to.map(&:downcase).include?(address.downcase) }
        .flat_map { |mail| (mail.html_part || mail).body.decoded.scan(%r{/auth/#{provider}/merge_using_email_link/[\w-]+}) }
        .uniq
    end

    def follow_merge_links_of(address)
      merge_links_sent_to(address).each do |link|
        @request.reset_session
        get :merge_using_email_link, params: { provider:, email_merge_token: link.split('/').last }
      end
    end

    before { ActionMailer::Base.deliveries.clear }

    def request_merge(email:, password: nil)
      perform_enqueued_jobs do
        post :send_email_merge_request, params: { merge_token:, email:, password:, provider: }.compact
      end
    end

    context 'without password' do
      before { request_merge(email: account.email) }

      it 'asks for the password of the account and sends no merge link' do
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:confirm_email_merge_password)
        expect(merge_links_sent_to(account.email)).to be_empty
        expect(merge_links_sent_to(email)).to be_empty
        expect(fci.reload.requested_email).to be_nil
      end
    end

    context 'with a wrong password' do
      before { request_merge(email: account.email, password: 'not the password') }

      it 'sends no merge link and counts the failed attempt' do
        expect(response).to render_template(:confirm_email_merge_password)
        expect(flash[:alert]).to eq(I18n.t('omniauth.flash.invalid_password'))
        expect(merge_links_sent_to(account.email)).to be_empty
        expect(account.reload.failed_attempts).to eq(1)
      end
    end

    context 'with the password of the account' do
      let!(:account) { create(:user, email: 'account@a.com', password: SECURE_PASSWORD) }

      before { request_merge(email: account.email, password: SECURE_PASSWORD) }

      it 'sends the merge link to the account address only' do
        expect(merge_links_sent_to(account.email)).to be_present
        expect(merge_links_sent_to(email)).to be_empty
      end

      it 'links the provider identity to the account when the link is followed' do
        follow_merge_links_of(account.email)

        expect(fci.reload.user).to eq(account)
        expect(controller.current_user).to eq(account)
      end
    end
  end

  describe '#send_email_merge_request with an unused email' do
    include ActiveJob::TestHelper

    let(:fci) { FranceConnectInformation.create!(user_info) }
    let(:merge_token) { fci.create_merge_token! }
    let(:new_email) { 'new_account@a.com' }

    before { ActionMailer::Base.deliveries.clear }

    subject do
      perform_enqueued_jobs do
        post :send_email_merge_request, params: { merge_token:, email: " #{new_email.upcase} ", provider: }
      end
    end

    it 'creates no account before the address is confirmed' do
      expect { subject }.not_to change { User.count }
      expect(controller.current_user).to be_nil
      expect(response).to redirect_to(root_path)
    end

    it 'creates the verified account when the link sent to this address is followed' do
      subject
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([new_email])

      get :merge_using_email_link, params: { provider:, email_merge_token: fci.reload.email_merge_token }

      expect(fci.reload.user.email).to eq(new_email)
      expect(fci.user.email_verified_at).to be_present
      expect(controller.current_user).to eq(fci.user)
    end
  end

  describe '#resend_and_renew_merge_confirmation' do
    let(:fci) { FranceConnectInformation.create!(user_info) }
    let(:merge_token) { fci.create_merge_token! }
    it 'renew token' do
      expect { post :resend_and_renew_merge_confirmation, params: { merge_token:, provider: } }.to change { fci.reload.merge_token }
      expect(response).to redirect_to(omniauth_merge_path(provider, fci.reload.merge_token))
    end

    # pf: régression prod 2026-07 — le mail partait avec un email_merge_token nil
    # (jamais créé sur ce chemin), son rendu échouait en job et l'usager ne
    # recevait jamais le mail de fusion.
    it 'creates the email_merge_token and sends the mail with it' do
      mailer_double = double('mailer', deliver_later: nil)
      expect(UserMailer).to receive(:omniauth_merge_confirmation)
        .with(fci.email_france_connect, kind_of(String), kind_of(Time), provider)
        .and_return(mailer_double)

      expect { post :resend_and_renew_merge_confirmation, params: { merge_token:, provider: } }
        .to change { fci.reload.email_merge_token }.from(nil)
    end

    it 'links the provider identity to the account of the provider email when the link is followed' do
      account = create(:user, email: email.downcase)
      post :resend_and_renew_merge_confirmation, params: { merge_token:, provider: }

      get :merge_using_email_link, params: { provider:, email_merge_token: fci.reload.email_merge_token }

      expect(fci.reload.user).to eq(account)
      expect(controller.current_user).to eq(account)
    end
  end
end
