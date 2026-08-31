# frozen_string_literal: true

describe 'users/dossiers/merci', type: :view do
  let(:procedure) { create(:procedure, :published, :with_dossier_submitted_message) }
  let(:dossier) { create(:dossier, :en_construction, procedure: procedure) }
  let(:message) { procedure.active_dossier_submitted_message }

  subject { render 'users/dossiers/merci', dossier: dossier, procedure: procedure }

  context 'when the message is plain text' do
    before { message.update!(message_on_submit_by_usager: "Merci, on s'occupe de tout.") }

    it { is_expected.to have_text("Merci, on s'occupe de tout.") }
  end

  context 'when the message contains a bare URL' do
    before { message.update!(message_on_submit_by_usager: "Pensez à déclarer votre escale sur https://escales.gov.pf avant l'arrivée.") }

    it 'turns the URL into a link opening in a new tab' do
      is_expected.to have_link('https://escales.gov.pf', href: 'https://escales.gov.pf')
      is_expected.to have_css('a[href="https://escales.gov.pf"][target="_blank"][rel~="noopener"]')
    end
  end

  context 'when the message contains markdown' do
    before { message.update!(message_on_submit_by_usager: "Dernière étape : **déclarer votre escale** sur [Escales](https://escales.gov.pf).") }

    it 'renders markdown links and emphasis' do
      is_expected.to have_link('Escales', href: 'https://escales.gov.pf')
      is_expected.to have_css('strong', text: 'déclarer votre escale')
    end
  end

  context 'when the message contains hostile HTML' do
    before { message.update!(message_on_submit_by_usager: "Bonjour <script>alert('x')</script> <a href=\"javascript:alert(1)\">clic</a>") }

    it 'sanitizes it' do
      is_expected.not_to have_css('script')
      is_expected.not_to have_css('a[href^="javascript:"]')
      expect(rendered).not_to include('<script>')
    end
  end

  context 'when there is no message' do
    let(:procedure) { create(:procedure, :published) }

    it { expect { subject }.not_to raise_error }
  end
end
