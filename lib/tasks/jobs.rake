# frozen_string_literal: true

namespace :jobs do
  desc 'Schedule all schedulable cron jobs'
  task schedule: :environment do
    schedulable_jobs.each(&:schedule)
  end

  desc 'Display schedule for all schedulable cron jobs'
  task display_schedule: :environment do
    schedulable_jobs.each(&:display_schedule)
  end

  desc 'Remove orphaned cron jobs from Sidekiq::Cron (classes no longer in codebase)'
  task remove_orphaned: :environment do
    orphaned = Sidekiq::Cron::Job.all.filter do |job|
      job.klass.safe_constantize.nil?
    end

    if orphaned.empty?
      puts "No orphaned cron jobs found."
    else
      orphaned.each do |job|
        puts "Removing orphaned cron job: #{job.name}"
        job.destroy
      end
      puts "Done. Removed #{orphaned.size} orphaned cron job(s)."
    end
  end

  def schedulable_jobs
    glob = Rails.root.join('app', 'jobs', '**', '*_job.rb')
    Dir.glob(glob).each { |f| require f }
    Cron::CronJob.descendants.filter(&:schedulable?)
  end
end
