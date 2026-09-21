# frozen_string_literal: true

require "rails_helper"

module Maintenance
  RSpec.describe T20260921replaceInternalClusterHostInCommentairesTask do
    let(:task) { described_class.new }
    let(:internal_host) { 'mes-demarches-production-mesdemarches-app.ds-production.svc.cluster.local' }
    let(:dossier) { create(:dossier, :accepte) }
    let(:instructeur) { create(:instructeur) }
    let(:automated_instructeur) { create(:instructeur, email: AUTOMATED_SENDER_EMAILS.first) }

    let!(:mirror_with_internal_link) do
      create(:commentaire, dossier:, email: CONTACT_EMAIL,
        body: "<p>[Votre dossier n° 1 a été accepté]</p><p>Attestation : <a href=\"https://#{internal_host}/dossiers/#{dossier.id}/attestation\">https://#{internal_host}/dossiers/#{dossier.id}/attestation</a></p>")
    end
    let!(:robot_with_internal_link) do
      create(:commentaire, dossier:, instructeur: automated_instructeur, body: "Voir http://#{internal_host}:3000/dossiers/#{dossier.id} et https://example.org/autre")
    end
    let!(:mirror_with_public_link) do
      create(:commentaire, dossier:, email: CONTACT_EMAIL, body: "<p><a href=\"https://#{ENV['APP_HOST']}/dossiers/#{dossier.id}\">lien</a></p>")
    end
    let!(:human_message) { create(:commentaire, dossier:, instructeur:, body: "Bonjour, rien à voir avec le cluster") }

    describe "#collection" do
      it "ne retient que les commentaires dont le corps contient un hôte interne du cluster" do
        expect(task.collection).to contain_exactly(mirror_with_internal_link, robot_with_internal_link)
      end
    end

    describe "#process" do
      it "remplace l'hôte interne par APP_HOST en conservant le schéma et le chemin" do
        task.process(mirror_with_internal_link)

        body = mirror_with_internal_link.reload.body
        expect(body).to include("https://#{ENV['APP_HOST']}/dossiers/#{dossier.id}/attestation")
        expect(body).not_to include('svc.cluster.local')
      end

      it "retire le port interne et laisse intacts les autres liens" do
        task.process(robot_with_internal_link)

        body = robot_with_internal_link.reload.body
        expect(body).to eq("Voir http://#{ENV['APP_HOST']}/dossiers/#{dossier.id} et https://example.org/autre")
      end

      it "ne touche pas au dossier ni aux horodatages du commentaire" do
        dossier_updated_at = dossier.reload.updated_at
        commentaire_updated_at = mirror_with_internal_link.updated_at

        task.process(mirror_with_internal_link)

        expect(dossier.reload.updated_at).to eq(dossier_updated_at)
        expect(mirror_with_internal_link.reload.updated_at).to eq(commentaire_updated_at)
      end
    end
  end
end
