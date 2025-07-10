# frozen_string_literal: true

class DraftNotificationJob < ApplicationJob
  # Coefficient pour calculer le délai : estimation_durée * 2
  DRAFT_NOTIFICATION_DELAY_MULTIPLIER = 2

  def self.schedule_for_dossier(dossier)
    delay_minutes = calculate_delay(dossier)
    set(wait: delay_minutes.minutes).perform_later(dossier.id)
  end

  def perform(dossier_id)
    dossier = Dossier.find_by(id: dossier_id)
    return unless dossier

    # Envoyer l'email seulement si le dossier est toujours en brouillon
    if dossier.brouillon?
      DossierMailer.with(dossier: dossier).notify_new_draft.deliver_now
    end
  end

  private

  def self.calculate_delay(dossier)
    delay_minutes = (dossier.revision.estimated_fill_duration / 60.0 * DRAFT_NOTIFICATION_DELAY_MULTIPLIER).round
    [1, delay_minutes].max # Minimum 1 minute
  end
end