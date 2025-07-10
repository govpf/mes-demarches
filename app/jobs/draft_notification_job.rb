# frozen_string_literal: true

class DraftNotificationJob < ApplicationJob
  # Coefficient pour calculer le délai : estimation_durée * 2
  DRAFT_NOTIFICATION_DELAY_MULTIPLIER = 2

  def perform(dossier_id)
    dossier = Dossier.find_by(id: dossier_id)
    return unless dossier

    # Envoyer l'email seulement si le dossier est toujours en brouillon
    if dossier.brouillon?
      DossierMailer.with(dossier: dossier).notify_new_draft.deliver_now
    end
  end
end