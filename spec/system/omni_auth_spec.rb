# frozen_string_literal: true

describe 'Omni Auth Connexion' do
  let(:code) { 'plop' }
  let(:given_name) { 'titi' }
  let(:family_name) { 'toto' }
  let(:birthdate) { '20150821' }
  let(:gender) { 'M' }
  let(:birthplace) { '1234' }
  let(:email) { 'plop@plop.com' }
  let(:france_connect_particulier_id) { 'blabla' }

  let(:user_info) do
    {
      france_connect_particulier_id: france_connect_particulier_id,
      given_name: given_name,
      family_name: family_name,
      birthdate: birthdate,
      birthplace: birthplace,
      gender: gender,
      email_france_connect: email,
    }
  end

  context 'when user is on login page' do
    before do
      ENV['GOOGLE_CLIENT_ID'] = "MyClientId"
      ENV['GOOGLE_CLIENT_SECRET'] = "MySecret"
      visit new_user_session_path
    end

    scenario 'link to Google is present' do
      expect(page).to have_link('Gmail')
    end

    context 'and click on gmail link' do
      let(:code) { 'plop' }

      context 'when authentification is ok' do
        before do
          # pf: sécurité (F2) — simule l'écho du state par le provider : l'URL de callback
          # reçoit le state généré au login, pour passer la validation anti-CSRF.
          allow(OmniAuthService).to receive(:authorization_uri) do |_provider, state:, **|
            omniauth_callback_path(provider: 'google', code: code, state: state)
          end
          allow(OmniAuthService).to receive(:retrieve_user_informations).and_return(france_connect_information)
        end

        context 'when no user is linked' do
          let(:france_connect_information) { build(:france_connect_information, user_info) }

          context 'and no user has the same email' do
            before do
              page.find("a[href='#{omniauth_path('google')}']").click
            end

            scenario 'he is redirected to user dossiers page', js: true do
              expect(page).to have_content("Choisissez votre adresse électronique de contact pour finaliser votre connexion")

              find('label', text: "Oui, utiliser #{email} comme adresse électronique de contact").click
              click_on 'Valider'

              expect(page).to have_content('Dossiers')
            end
          end

          context 'and an user exists with the same email' do
            let!(:user) { create(:user, email: email, password: SECURE_PASSWORD) }

            before do
              page.find("a[href='#{omniauth_path('google')}']").click
            end

            scenario 'he is redirected to the merge page' do
              expect(page).to have_content('Fusion des comptes')
            end

            scenario 'it merges its account', js: true do
              find('label[for="it-is-mine"]').click

              expect(page).to have_css('.fusion', visible: true, wait: 2)

              within '.fusion' do
                fill_in 'password', with: SECURE_PASSWORD
                click_on 'Fusionner les comptes'
              end

              expect(page).to have_content('Dossiers')
            end

            scenario 'it uses another email that belongs to nobody' do
              page.find('#it-is-not-mine').click
              fill_in 'email', with: 'new_email@a.com'
              click_on 'Utiliser cette adresse électronique'

              expect(page).to have_content('Dossiers')
            end

            context 'and the user wants an email that belongs to another account', js: true do
              let!(:another_user) { create(:user, email: 'an_existing_email@a.com', password: SECURE_PASSWORD) }

              scenario 'it uses another email that belongs to another account' do
                find('label[for="it-is-not-mine"]').click

                expect(page).to have_css('.new-account', visible: true)

                within '.new-account' do
                  fill_in 'email', with: 'an_existing_email@a.com'
                  click_on 'Utiliser cette adresse électronique'
                end

                expect(page).to have_content('Nous venons de vous envoyer le mail de confirmation')
              end
            end
          end
        end

        context 'when a user is linked' do
          let!(:france_connect_information) do
            create(:france_connect_information, :with_user, user_info.merge(created_at: Time.zone.parse('12/12/2012'), updated_at: Time.zone.parse('12/12/2012')))
          end

          before do
            page.find("a[href='#{omniauth_path('google')}']").click
          end

          scenario 'he is redirected to user dossiers page' do
            expect(page).to have_content('Dossiers')
          end

          scenario 'the updated_at date is well updated' do
            expect(france_connect_information.reload.updated_at).not_to eq(france_connect_information.created_at)
          end
        end
      end

      context 'when authentification is not ok' do
        before do
          # pf: sécurité (F2) — simule l'écho du state par le provider : l'URL de callback
          # reçoit le state généré au login, pour passer la validation anti-CSRF.
          allow(OmniAuthService).to receive(:authorization_uri) do |_provider, state:, **|
            omniauth_callback_path(provider: 'google', code: code, state: state)
          end
          allow(OmniAuthService).to receive(:retrieve_user_informations) { raise Rack::OAuth2::Client::Error.new(500, error: 'Unknown') }
          page.find("a[href='#{omniauth_path('google')}']").click
        end

        scenario 'he is redirected to login page' do
          expect(page).to have_css("a[href='#{omniauth_path('google')}']")
        end

        scenario 'error message is displayed' do
          expect(page).to have_content(I18n.t('errors.messages.omniauth.connexion', provider: I18n.t('omniauth.provider.google')))
        end
      end
    end
  end
end
