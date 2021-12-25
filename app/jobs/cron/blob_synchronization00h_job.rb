class Cron::BlobSynchronization00hJob < Cron::CronJob
  self.schedule_expression = "every day at midnight"

  def perform(*args)
    if ['1', '2'].include?(ENV.fetch('OUTSCALE_STEP'))
      S3Synchronization.synchronize(false, Time.zone.now + 135.minutes)
    end
  end
end
