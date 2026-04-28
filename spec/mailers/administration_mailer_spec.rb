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
        expect(subject[BalancerDeliveryMethod::BYPASS_UNVERIFIED_MAIL_PROTECTION]).to be_present
      end
    end

    describe "when the user is already active" do
      let(:last_sign_in_at) { Time.zone.now }
      it do
        expect(subject.body).not_to include(admin_activate_path(token: token))
        expect(subject.body).to include(edit_user_password_url(admin_user, reset_password_token: token))
      end
    end
  end

  describe '#procedure_published' do
    let(:procedure) { create(:procedure, :published) }

    subject { described_class.procedure_published(procedure) }

    it do
      expect(subject.subject).not_to be_empty
      expect(subject.to).to eq([EQUIPE_EMAIL])
      expect(subject[BalancerDeliveryMethod::BYPASS_UNVERIFIED_MAIL_PROTECTION]).to be_present
    end

    context 'with types de champ including repetition' do
      let(:procedure) do
        create(:procedure, :published, types_de_champ_public: [
          { type: :text, libelle: 'Nom' },
          { type: :repetition, libelle: 'Répétition', children: [{ type: :text, libelle: 'Champ enfant' }] },
        ])
      end

      it 'renders the email body without error' do
        expect(subject.body.encoded).to include('Nom')
        expect(subject.body.encoded).to include('Répétition')
      end
    end
  end

  describe '#refuse_admin' do
    let(:mail) { "l33t-4dm1n@h4x0r.com" }

    subject { described_class.refuse_admin(mail) }

    it do
      expect(subject.subject).not_to be_empty
      expect(subject[BalancerDeliveryMethod::BYPASS_UNVERIFIED_MAIL_PROTECTION]).to be_present
    end
  end
end
