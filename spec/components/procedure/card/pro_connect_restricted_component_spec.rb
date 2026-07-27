# frozen_string_literal: true

require "rails_helper"

RSpec.describe Procedure::Card::ProConnectRestrictedComponent, type: :component do
  before do
    allow_any_instance_of(described_class).to receive(:feature_enabled?).and_return(true)
  end

  subject { render_inline(described_class.new(procedure:)) }

  let(:procedure) { create(:procedure, pro_connect_restriction: restriction_level) }

  context "when no restriction" do
    let(:restriction_level) { :none }

    it do
      # pf: titre adapté Microsoft @administration.gov.pf au lieu de "ProConnect"
      is_expected.to have_css('.fr-badge', text: "Aucune restriction")
      is_expected.to have_css('h3.fr-h6', text: "Authentification professionnelle")
    end
  end

  context "when restriction for instructeurs" do
    let(:restriction_level) { :instructeurs }

    it do
      is_expected.to have_css('.fr-badge.fr-badge--success', text: "Administrateurs et instructeurs")
      is_expected.to have_css('h3.fr-h6', text: "Authentification professionnelle")
    end
  end

  context "when restriction for all users" do
    let(:restriction_level) { :all }

    it do
      is_expected.to have_css('.fr-badge.fr-badge--success', text: "Tous les utilisateurs")
      is_expected.to have_css('h3.fr-h6', text: "Authentification professionnelle")
    end
  end
end
