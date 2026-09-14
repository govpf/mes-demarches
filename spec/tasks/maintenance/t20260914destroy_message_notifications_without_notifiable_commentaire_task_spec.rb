# frozen_string_literal: true

require "rails_helper"

module Maintenance
  RSpec.describe T20260914destroyMessageNotificationsWithoutNotifiableCommentaireTask do
    let(:task) { described_class.new }
    let(:instructeur) { create(:instructeur) }
    let(:automated_instructeur) { create(:instructeur, email: AUTOMATED_SENDER_EMAILS.first) }

    let(:dossier_robot_only) { create(:dossier, :en_construction) }
    let(:dossier_with_usager_message) { create(:dossier, :en_construction) }
    let(:dossier_with_own_message_only) { create(:dossier, :en_construction) }
    let(:dossier_with_colleague_message) { create(:dossier, :en_construction) }

    let!(:notif_robot_only) { create(:dossier_notification, dossier: dossier_robot_only, instructeur:, notification_type: :message) }
    let!(:notif_usager) { create(:dossier_notification, dossier: dossier_with_usager_message, instructeur:, notification_type: :message) }
    let!(:notif_own_only) { create(:dossier_notification, dossier: dossier_with_own_message_only, instructeur:, notification_type: :message) }
    let!(:notif_colleague) { create(:dossier_notification, dossier: dossier_with_colleague_message, instructeur:, notification_type: :message) }
    let!(:notif_other_type) { create(:dossier_notification, dossier: dossier_robot_only, instructeur:, notification_type: :dossier_modifie) }

    before do
      CommentaireService.create!(automated_instructeur, dossier_robot_only, body: 'automate')
      CommentaireService.create!(CONTACT_EMAIL, dossier_robot_only, body: 'système')

      CommentaireService.create!(automated_instructeur, dossier_with_usager_message, body: 'automate')
      create(:commentaire, dossier: dossier_with_usager_message)

      CommentaireService.create!(instructeur, dossier_with_own_message_only, body: 'moi')

      CommentaireService.create!(create(:instructeur), dossier_with_colleague_message, body: 'collègue')
    end

    describe "#collection" do
      it "ne retient que les notifications message sans aucun commentaire notifiable pour l'instructeur" do
        expect(task.collection).to contain_exactly(notif_robot_only, notif_own_only)
      end
    end

    describe "#process" do
      it "supprime la notification" do
        expect { task.process(notif_robot_only) }.to change { DossierNotification.exists?(notif_robot_only.id) }.from(true).to(false)
      end
    end
  end
end
