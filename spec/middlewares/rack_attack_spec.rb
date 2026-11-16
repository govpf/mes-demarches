# frozen_string_literal: true

describe Rack::Attack, type: :request do
  include Devise::Test::IntegrationHelpers

  let(:limit) { 30 }
  let(:period) { 15 }
  let(:ip) { "1.2.3.4" }

  before(:each) do
    ENV['RACK_ATTACK_ENABLE'] = 'true'
    setup_rack_attack_cache_store
    avoid_test_overlaps_in_cache
  end

  after do
    ENV['RACK_ATTACK_ENABLE'] = 'false'
  end

  def setup_rack_attack_cache_store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  def avoid_test_overlaps_in_cache
    Rails.cache.clear
  end

  context '/users/sign_in' do
    before do
      limit.times do
        Rack::Attack.cache.count("/users/sign_in/ip:#{ip}", period)
      end
    end

    subject do
      post "/users/sign_in", headers: { 'X-Forwarded-For': ip }
    end

    it "throttle excessive requests by IP address" do
      subject

      expect(response).to have_http_status(:too_many_requests)
    end

    context 'when the ip is whitelisted' do
      before do
        allow(IPService).to receive(:ip_trusted?).and_return(true)
        allow(ProConnectService).to receive(:enabled?).and_return(false)
        allow_any_instance_of(Users::SessionsController).to receive(:create).and_return(:ok)
      end

      it "respects the whitelist" do
        subject

        expect(response).not_to have_http_status(:too_many_requests)
      end
    end
  end

  context 'verification links' do
    let(:limit) { 20 }
    let(:period) { 60 }

    before do
      limit.times do
        Rack::Attack.cache.count("verification_links/ip:#{ip}", period)
      end
    end

    it "throttle excessive requests on the attestation qrcode" do
      get "/dossiers/123/qrcode/01234567-89abcdef", headers: { 'X-Forwarded-For': ip }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "throttle excessive requests on the piece justificative download" do
      get "/champs/123/456/piece_justificative/download/01234567-89abcdef/0", headers: { 'X-Forwarded-For': ip }

      expect(response).to have_http_status(:too_many_requests)
    end

    it "shares the counter between both links, but not with other pages" do
      get "/users/sign_in", headers: { 'X-Forwarded-For': ip }

      expect(response).not_to have_http_status(:too_many_requests)
    end

    it "does not throttle another ip" do
      get "/dossiers/123/qrcode/01234567-89abcdef", headers: { 'X-Forwarded-For': "5.6.7.8" }

      expect(response).not_to have_http_status(:too_many_requests)
    end
  end

  context 'verification links ban' do
    let(:path) { "/dossiers/123/qrcode/01234567-89abcdef" }

    before do
      VerificationLinkAccessConcern::MAX_FAILURES.times do
        Rack::Attack::Fail2Ban.filter(VerificationLinkAccessConcern.ban_key(ip), maxretry: VerificationLinkAccessConcern::MAX_FAILURES, findtime: 600, bantime: 3600) { true }
      end
    end

    it "blocks an ip banned after too many wrong tokens" do
      get path, headers: { 'X-Forwarded-For': ip }

      expect(response).to have_http_status(:forbidden)
    end

    it "does not block the banned ip elsewhere" do
      get "/users/sign_in", headers: { 'X-Forwarded-For': ip }

      expect(response).not_to have_http_status(:forbidden)
    end

    it "does not block another ip" do
      get path, headers: { 'X-Forwarded-For': "5.6.7.8" }

      expect(response).not_to have_http_status(:forbidden)
    end
  end

  context 'verification links with wrong tokens' do
    let(:dossier) { create(:dossier, :with_attestation_acceptation) }
    let(:wrong_path) { "/dossiers/#{dossier.id}/qrcode/01234567-89abcdef" }

    before { sign_in(create(:user)) }

    it "bans the ip after too many wrong tokens, even for a valid link" do
      VerificationLinkAccessConcern::MAX_FAILURES.times do
        get wrong_path, headers: { 'X-Forwarded-For': ip }
        expect(response).to have_http_status(:ok)
      end

      get "/dossiers/#{dossier.id}/qrcode/#{dossier.verification_link_token}", headers: { 'X-Forwarded-For': ip }

      expect(response).to have_http_status(:forbidden)
    end

    it "does not count valid links as failures" do
      (VerificationLinkAccessConcern::MAX_FAILURES + 1).times do
        get "/dossiers/#{dossier.id}/qrcode/#{dossier.verification_link_token}", headers: { 'X-Forwarded-For': ip }
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
