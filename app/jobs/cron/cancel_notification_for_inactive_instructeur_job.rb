# frozen_string_literal: true

class Cron::CancelNotificationForInactiveInstructeurJob < Cron::CronJob
  self.schedule_expression = "from monday through friday at 3 am"

  def perform(*args)
    # pf: préférence portée par instructeurs_procedures depuis le bump 2026-01-06-01
    InstructeursProcedure.cancel_instant_email_new_dossier_for_inactive_instructeurs
  end
end
