# frozen_string_literal: true

require 'rails_helper'

RSpec.describe APILexpol do
  let(:use_test_user) { false }
  let(:numero_tahiti) { nil }
  let(:api_lexpol) { described_class.new("instructeur@mes-demarches.gov.pf", numero_tahiti, use_test_user) }

  before do
    allow(ENV).to receive(:fetch).with('LEXPOL_CERTIFICATE_ENABLED', "").and_return('')
    allow(ENV).to receive(:fetch).with('LEXPOL_EMAIL').and_return('fake_email@example.com')
    allow(ENV).to receive(:fetch).with('LEXPOL_PASSWORD').and_return('fake_password')
  end

  describe '#authenticate' do
    it 'retrieves a token from the API' do
      VCR.use_cassette('authenticate') do
        token = api_lexpol.authenticate
        expect(token).not_to be_nil
      end
    end
  end

  describe '#get_models' do
    it 'retrieves the list of models' do
      VCR.use_cassette('get_models') do
        models = api_lexpol.get_models
        expect(models).to be_an(Array)
      end
    end
  end

  describe '#create_dossier' do
    let(:modele_id) { 598706 }
    let(:variables) { { 'nom' => 'Test', 'description' => 'Test dossier' } }

    it 'creates a dossier and returns the NOR' do
      VCR.use_cassette('create_dossier') do
        nor = api_lexpol.create_dossier(modele_id, variables)
        expect(nor).to eq('ZZZ24000882TT')
      end
    end
  end

  describe '#update_dossier' do
    let(:nor) { 'ZZZ24000882TT' }
    let(:variables) { { 'nom' => 'Updated Test' } }

    it 'updates a dossier successfully' do
      VCR.use_cassette('update_dossier') do
        result = api_lexpol.update_dossier(nor, variables)
        expect(result).to eq(nor)
      end
    end
  end

  describe 'determine_email_agent' do
    before do
      allow(APILexpol).to receive(:service_emails).and_return({ '003970' => 'manager@example.com', '004200' => 'admin@other.gov.pf' })
    end

    context "when use_test_user = false" do
      let(:use_test_user) { false }
      it "keeps the provided email if no TAHITI is given" do
        expect(api_lexpol.instance_variable_get(:@email_agent)).to eq("instructeur@mes-demarches.gov.pf")
      end

      it "keeps the provided email if TAHITI is given" do
        local_api = described_class.new("usager@example.com", "003970", false)
        expect(local_api.instance_variable_get(:@email_agent)).to eq("usager@example.com")
      end
    end

    context "when use_test_user = true" do
      let(:use_test_user) { true }

      context "and a known TAHITI is provided" do
        let(:numero_tahiti) { "003970" }
        it "uses the corresponding service email" do
          expect(api_lexpol.instance_variable_get(:@email_agent)).to eq("manager@example.com")
        end
      end

      context "and an unknown TAHITI is provided" do
        let(:numero_tahiti) { "999999" }
        it "falls back to the initially given email" do
          expect(api_lexpol.instance_variable_get(:@email_agent)).to eq("instructeur@mes-demarches.gov.pf")
        end

        it "logs a warning about unknown SIRET" do
          expect(Rails.logger).to receive(:warn).with(/SIRET '999999' non trouvé/)
          described_class.new("instructeur@mes-demarches.gov.pf", "999999", true)
        end
      end

      context "and no TAHITI is provided (nil)" do
        let(:numero_tahiti) { nil }

        it "falls back to the initially given email" do
          expect(api_lexpol.instance_variable_get(:@email_agent)).to eq("instructeur@mes-demarches.gov.pf")
        end

        it "logs a warning about missing SIRET" do
          expect(Rails.logger).to receive(:warn).with(/aucun SIRET fourni/)
          described_class.new("instructeur@mes-demarches.gov.pf", nil, true)
        end
      end
    end
  end

  describe 'LexpolAccessDenied exception' do
    let(:api_lexpol) { described_class.new("test@example.com", nil, false) }

    context 'on authentication' do
      it 'raises LexpolAccessDenied on 401 error' do
        allow(Typhoeus).to receive(:post).and_return(
          double(success?: false, code: 401, body: 'Unauthorized')
        )

        expect {
          api_lexpol.send(:request_authentication)
        }.to raise_error(APILexpol::LexpolAccessDenied) do |error|
          expect(error.email_used).to eq("test@example.com")
          expect(error.http_code).to eq(401)
        end
      end

      it 'raises LexpolAccessDenied on 403 error' do
        allow(Typhoeus).to receive(:post).and_return(
          double(success?: false, code: 403, body: 'Forbidden')
        )

        expect {
          api_lexpol.send(:request_authentication)
        }.to raise_error(APILexpol::LexpolAccessDenied) do |error|
          expect(error.email_used).to eq("test@example.com")
          expect(error.http_code).to eq(403)
        end
      end

      it 'raises generic error on other HTTP errors' do
        allow(Typhoeus).to receive(:post).and_return(
          double(success?: false, code: 500, body: 'Internal Server Error')
        )

        expect {
          api_lexpol.send(:request_authentication)
        }.to raise_error(StandardError, /Erreur d'authentification Lexpol/)
      end
    end

    context 'on API request' do
      before do
        # Mock successful authentication
        allow(api_lexpol).to receive(:authenticate).and_return('fake_token')
      end

      it 'raises LexpolAccessDenied on 401 error' do
        allow_any_instance_of(Typhoeus::Request).to receive(:run).and_return(
          double(success?: false, code: 401, body: 'Unauthorized')
        )

        expect {
          api_lexpol.send(:request, :get, '/test', 'Test error')
        }.to raise_error(APILexpol::LexpolAccessDenied) do |error|
          expect(error.email_used).to eq("test@example.com")
          expect(error.http_code).to eq(401)
        end
      end

      it 'raises LexpolAccessDenied on 403 error' do
        allow_any_instance_of(Typhoeus::Request).to receive(:run).and_return(
          double(success?: false, code: 403, body: 'Forbidden')
        )

        expect {
          api_lexpol.send(:request, :get, '/test', 'Test error')
        }.to raise_error(APILexpol::LexpolAccessDenied) do |error|
          expect(error.email_used).to eq("test@example.com")
          expect(error.http_code).to eq(403)
        end
      end
    end
  end
end
