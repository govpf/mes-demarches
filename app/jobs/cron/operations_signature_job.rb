# frozen_string_literal: true

class Cron::OperationsSignatureJob < Cron::CronJob
  # Sentry Crons : signale les exécutions en échec ET les exécutions manquantes.
  # L'horodatage a été en panne 17 mois (04/2025→08/2026) sans qu'aucune alerte
  # ne remonte ; ce monitor rend la panne visible dès le lendemain.
  include Sentry::Cron::MonitorCheckIns

  self.schedule_expression = "every day at 06:00"

  sentry_monitor_check_ins(
    slug: 'operations-signature',
    monitor_config: Sentry::Cron::MonitorConfig.from_crontab(
      '0 6 * * *',
      checkin_margin: 60, # minutes de retard tolérées avant alerte « missed »
      max_runtime: 240, # minutes (rattrapage de plusieurs jours possible)
      timezone: 'Pacific/Tahiti'
    )
  )

  def perform(*args)
    start_date = DossierOperationLog.where(bill_signature: nil).order(:executed_at).pick(:executed_at).beginning_of_day
    last_midnight = Time.zone.now.beginning_of_day

    while start_date < last_midnight
      operations = DossierOperationLog
        .select(:id, :digest)
        .where(executed_at: start_date...start_date.tomorrow, bill_signature: nil)

      BillSignatureService.sign_operations(operations, start_date) if operations.present?

      start_date = start_date.tomorrow
    end
  end
end
