# frozen_string_literal: true

require "rails_helper"

module Maintenance
  RSpec.describe T20260824recomputeExpiredAtOnNonNotifiedDossiersTask do
    let(:task) { described_class.new }
    let(:procedure) { create(:procedure, duree_conservation_dossiers_dans_ds: 12) }

    let!(:stale_dossier) { create(:dossier, :accepte, procedure:, processed_at: 1.month.ago) }
    let!(:notified_dossier) { create(:dossier, :accepte, procedure:, processed_at: 1.month.ago, termine_close_to_expiration_notice_sent_at: 1.day.ago) }
    let!(:en_instruction_dossier) { create(:dossier, :en_instruction, procedure:) }

    describe "#collection" do
      it "ne retient que les dossiers sans avertissement envoyé, hors instruction" do
        expect(task.collection).to contain_exactly(stale_dossier)
      end
    end

    describe "#process" do
      it "recalcule expired_at avec la durée de conservation courante de la procédure" do
        # rallonge faite sans recalcul des dossiers : expired_at reste calculé sur l'ancienne durée
        procedure.update_column(:duree_conservation_dossiers_dans_ds, 36)

        task.process(stale_dossier.reload)

        expect(stale_dossier.reload.expired_at).to be_within(1.hour).of(35.months.from_now)
      end
    end
  end
end
