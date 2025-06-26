# frozen_string_literal: true

RSpec.describe AdministrationMailer, type: :mailer do
  describe '#invite_admin' do
    let(:admin_user) { create(:user, last_sign_in_at: last_sign_in_at) }
    let(:token) { "some_token" }
    let(:last_sign_in_at) { nil }

    subject { described_class.invite_admin(admin_user, token) }

    it { expect(subject.subject).not_to be_empty }

    describe "when the user has not been activated" do
      it do
        expect(subject.body).to include(users_activate_path(token: token))
        expect(subject.body).not_to include(edit_user_password_url(admin_user, reset_password_token: token))
        expect(subject['BYPASS_UNVERIFIED_MAIL_PROTECTION']).to be_present
      end
    end

    describe "when the user is already active" do
      let(:last_sign_in_at) { Time.zone.now }
      it { expect(subject.body).not_to include(users_activate_path(token: token)) }
      it { expect(subject.body).to include(edit_user_password_url(admin_user, reset_password_token: token)) }
    end
  end

  describe '#refuse_admin' do
    let(:mail) { "l33t-4dm1n@h4x0r.com" }

    subject { described_class.refuse_admin(mail) }

    it do
      expect(subject.subject).not_to be_empty
      expect(subject['BYPASS_UNVERIFIED_MAIL_PROTECTION']).to be_present
    end
  end

  describe '#procedure_published' do
    let(:procedure) { create(:procedure, :published, libelle: "Test Procédure") }
    let!(:type_de_champ) { create(:type_de_champ, libelle: "IBAN", description: "Votre compte bancaire", procedure: procedure) }
    let!(:type_de_champ_no_desc) { create(:type_de_champ, libelle: "Nom", description: "", procedure: procedure) }

    subject { described_class.procedure_published(procedure) }

    it 'sends email to EQUIPE_EMAIL' do
      expect(subject.to).to include(EQUIPE_EMAIL)
    end

    context 'when procedure has suspicious keywords from DubiousProcedure' do
      let!(:suspicious_champ) { create(:type_de_champ, libelle: "Numéro de sécurité sociale", type_champ: :text, procedure: procedure) }

      it 'shows dubious procedure alert' do
        expect(subject.body.encoded).to include("Procédure suspecte détectée")
        expect(subject.body.encoded).to include("sécurité sociale")
      end
    end

    context 'when less than 50% of champs have descriptions' do
      before do
        create(:type_de_champ, libelle: "Autre champ", description: "", procedure: procedure)
      end

      it 'shows low description coverage alert' do
        expect(subject.body.encoded).to include("Moins de 50% des champs ont une description")
      end
    end
  end
end
