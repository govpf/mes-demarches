# frozen_string_literal: true

class DossierModificationNotificationJob < ApplicationJob
  # Délai fixe pour l'envoi des emails concernant la modification de dossier
  DOSSIER_MODIFICATION_NOTIFICATION_DELAY_MINUTES = 6

  def self.schedule_for_dossier(dossier)
    set(wait: DOSSIER_MODIFICATION_NOTIFICATION_DELAY_MINUTES.minutes).perform_later(dossier.id)
  end

  def perform(dossier_id)
    dossier = Dossier.find_by(id: dossier_id)
    return unless dossier
    return unless should_send_notification?(dossier)

    NotificationMailer.send_dossier_modification_notification(dossier).deliver_now
  end

  private

  def should_send_notification?(dossier)
    if dossier.last_commentaire_updated_at.present? && dossier.last_commentaire_updated_at > dossier.last_champ_updated_at
      false
    else
      true
    end
  end
end
