# frozen_string_literal: true

class InstructionNotificationJob < ApplicationJob
  # Délai fixe pour l'envoi des emails d'instruction
  INSTRUCTION_NOTIFICATION_DELAY_MINUTES = 15

  def self.schedule_for_dossier(dossier)
    set(wait: INSTRUCTION_NOTIFICATION_DELAY_MINUTES.minutes).perform_later(dossier.id)
  end

  def perform(dossier_id)
    dossier = Dossier.find_by(id: dossier_id)
    return unless dossier

    # Envoyer l'email seulement si le dossier est toujours en instruction
    if dossier.en_instruction?
      NotificationMailer.send_en_instruction_notification(dossier).deliver_now
    end
  end
end
