# frozen_string_literal: true

require 'spec_helper'

describe OmniAuthService do
  describe '.trusted_email_assertion?' do
    # pf: sécurité (F3/F4) — détermine si l'email asserté par le provider est digne
    # de confiance, pour autoriser une fusion/connexion sans mot de passe.
    subject { described_class.trusted_email_assertion?(provider:, email_verified:, tid:) }

    let(:email_verified) { nil }
    let(:tid) { nil }

    context 'providers à identité forte' do
      let(:tid) { nil }

      %w[tatou sipf].each do |strong_provider|
        context "avec #{strong_provider}" do
          let(:provider) { strong_provider }

          it { is_expected.to be(true) }
        end
      end
    end

    context 'google / yahoo (sous condition email_verified)' do
      let(:provider) { 'google' }

      context 'email_verified vrai (booléen)' do
        let(:email_verified) { true }

        it { is_expected.to be(true) }
      end

      context 'email_verified vrai (chaîne)' do
        let(:email_verified) { 'true' }

        it { is_expected.to be(true) }
      end

      context 'email_verified faux ou absent' do
        let(:email_verified) { nil }

        it { is_expected.to be(false) }
      end
    end

    context 'microsoft (sous condition tid ∈ allowlist)' do
      let(:provider) { 'microsoft' }

      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('MICROSOFT_ALLOWED_TENANTS', '').and_return('tenant-gov-pf, tenant-idt-pf')
      end

      context 'tid dans l’allowlist' do
        let(:tid) { 'tenant-idt-pf' }

        it { is_expected.to be(true) }
      end

      context 'tid hors allowlist (nOAuth : tenant attaquant)' do
        let(:tid) { 'tenant-attaquant' }

        it { is_expected.to be(false) }
      end
    end

    context 'microsoft avec MICROSOFT_ALLOWED_TENANTS vide (fail-safe)' do
      let(:provider) { 'microsoft' }
      let(:tid) { 'tenant-idt-pf' }

      before do
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with('MICROSOFT_ALLOWED_TENANTS', '').and_return('')
      end

      it 'ne fait jamais confiance par défaut' do
        is_expected.to be(false)
      end
    end
  end

  describe '.retrieve_user_informations' do
    let(:code) { 'plop' }
    let(:access_token) { instance_double('OpenIDConnect::AccessToken') }

    let(:given_name) { 'plop1' }
    let(:family_name) { 'plop2' }
    let(:birthdate) { '2012-12-31' }
    let(:gender) { 'plop4' }
    let(:birthplace) { 'plop5' }
    let(:email) { 'plop@emaiL.com' }
    let(:phone) { '012345678' }
    let(:france_connect_particulier_id) { 'izhikziogjuziegj' }

    let(:user_info_hash) { { sub: france_connect_particulier_id, given_name: given_name, family_name: family_name, birthdate: birthdate, gender: gender, birthplace: birthplace, email: email, phone: phone } }
    let(:user_info) { instance_double('OpenIDConnect::ResponseObject::UserInfo', raw_attributes: user_info_hash) }

    subject { described_class.retrieve_user_informations 'google', code }

    before do
      allow_any_instance_of(OmniAuthClient).to receive(:access_token!).and_return(access_token)
      allow(access_token).to receive(:userinfo!).and_return(user_info)
    end

    it 'set code for OmniAuthClient' do
      expect_any_instance_of(OmniAuthClient).to receive(:authorization_code=).with(code)
      subject
    end

    it 'returns user informations' do
      expect(subject).to have_attributes({
        given_name:                    given_name,
        family_name:                   family_name,
        birthdate:                     Time.zone.parse(birthdate).to_date,
        birthplace:                    birthplace,
        gender:                        gender,
        email_france_connect:          email,
        france_connect_particulier_id: france_connect_particulier_id,
      })
    end
  end
end
