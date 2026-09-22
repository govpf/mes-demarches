# frozen_string_literal: true

require "rails_helper"

module Maintenance
  RSpec.describe T20260921destroySeenDossierModifieNotificationsTask do
    let(:task) { described_class.new }
    let(:instructeur) { create(:instructeur) }
    let(:procedure) do
      create(:procedure, :published, :for_individual,
        types_de_champ_public: [{ type: :text, libelle: 'Nom' }],
        types_de_champ_private: [{ type: :piece_justificative, libelle: 'Courrier' }])
    end
    let(:depose_at) { 10.days.ago }
    let(:seen_at) { 5.days.ago }

    def dossier_with_follow(state: :accepte)
      dossier = create(:dossier, state, :with_individual, procedure:, depose_at:)
      dossier.champs.update_all(updated_at: depose_at)
      dossier.update_columns(last_champ_updated_at: depose_at, identity_updated_at: nil)
      create(:follow, instructeur:, dossier:, demande_seen_at: seen_at)
      dossier
    end

    def notification_for(dossier)
      create(:dossier_notification, dossier:, instructeur:, notification_type: :dossier_modifie)
    end

    def touch_champ(dossier, private:, at:)
      champ = private ? dossier.project_champs_private.first : dossier.project_champs_public.first
      champ.update_columns(updated_at: at)
      dossier.update_columns(last_champ_updated_at: at)
    end

    # pf: séquence observée en prod : consultation, puis PJ privée déposée en web (bump indu), puis suivi
    let!(:notif_private_pj_after_seen) do
      dossier = dossier_with_follow
      touch_champ(dossier, private: true, at: seen_at + 1.hour)
      notification_for(dossier)
    end
    let!(:notif_public_change_before_seen) do
      dossier = dossier_with_follow
      touch_champ(dossier, private: false, at: seen_at - 1.day)
      notification_for(dossier)
    end
    let!(:notif_public_change_after_seen) do
      dossier = dossier_with_follow
      touch_champ(dossier, private: false, at: seen_at + 1.hour)
      notification_for(dossier)
    end
    let!(:notif_identity_updated_after_seen) do
      dossier = dossier_with_follow
      dossier.update_columns(identity_updated_at: seen_at + 1.hour)
      notification_for(dossier)
    end
    let!(:notif_without_follow) do
      dossier = create(:dossier, :accepte, :with_individual, procedure:, depose_at:)
      notification_for(dossier)
    end
    let!(:notif_other_type) do
      dossier = dossier_with_follow
      create(:dossier_notification, dossier:, instructeur:, notification_type: :message)
    end

    describe "#collection" do
      it "ne retient que les tags dont la demande a été consultée après la dernière modification publique" do
        expect(task.collection).to contain_exactly(notif_private_pj_after_seen, notif_public_change_before_seen)
      end
    end

    describe "#process" do
      it "supprime la notification" do
        expect { task.process(notif_private_pj_after_seen) }
          .to change { DossierNotification.exists?(notif_private_pj_after_seen.id) }.from(true).to(false)
      end
    end
  end
end
