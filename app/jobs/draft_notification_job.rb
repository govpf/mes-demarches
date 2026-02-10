# frozen_string_literal: true

class DraftNotificationJob < ApplicationJob
  # Coefficient pour calculer le délai : estimation_durée * 2
  DRAFT_NOTIFICATION_DELAY_MULTIPLIER = 3

  def self.schedule_for_dossier(dossier)
    delay_minutes = calculate_delay(dossier)
    set(wait: delay_minutes.minutes).perform_later(dossier.id)
  end

  def perform(dossier_id)
    dossier = Dossier.find_by(id: dossier_id)
    return unless dossier

    # pf: logs de diagnostic pour comprendre l'exécution
    Rails.logger.info "[DraftNotificationJob] Dossier #{dossier_id}: state=#{dossier.state}, created_at=#{dossier.created_at}, depose_at=#{dossier.depose_at}, updated_at=#{dossier.updated_at}"

    # Envoyer l'email seulement si le dossier est toujours en brouillon
    if should_send_notification?(dossier)
      Rails.logger.info "[DraftNotificationJob] Sending draft notification for dossier #{dossier_id}"
      DossierMailer.with(dossier: dossier).notify_new_draft.deliver_now
    else
      Rails.logger.info "[DraftNotificationJob] Skipping draft notification for dossier #{dossier_id} - state is #{dossier.state}"
    end
  end

  private

  def self.calculate_delay(dossier)
    delay_minutes = (dossier.revision.estimated_fill_duration / 60.0 * DRAFT_NOTIFICATION_DELAY_MULTIPLIER).round
    [5, delay_minutes].max # Minimum 1 minute
  end

  # pf: condition étendue avec hidden_by_user_at (inspiré de upstream PR #179)
  def should_send_notification?(dossier)
    dossier.brouillon? && dossier.hidden_by_user_at.blank?
  end
end
