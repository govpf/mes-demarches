module Swarm
  class Migration
    def migrate(context)
      @context = context || ''
      with_advisory_lock { migrate_without_lock }
    end

    private

    def migrate_without_lock
      # skip annotate task else process hangs in dev env when another task has accessed database
      ENV['ANNOTATE_SKIP_ON_DB_MIGRATE'] = '1'

      puts "#{@context} Database migration"
      Rake::Task['db:migrate'].invoke
      puts "#{@context} After_party migration"
      Rake::Task['after_party:run'].invoke
      puts "#{@context} Cron task setup"
      Rake::Task['jobs:schedule'].invoke
      puts "#{@context} Migrations successful"
    end

    def with_advisory_lock
      lock_id = generate_migrator_advisory_lock_id
      MDAdvisoryLockBase.establish_connection(ActiveRecord::Base.connection_config) unless MDAdvisoryLockBase.connected?
      connection = MDAdvisoryLockBase.connection
      got_lock = connection.get_advisory_lock(lock_id)
      raise ActiveRecord::ConcurrentMigrationError unless got_lock
      yield
    ensure
      if got_lock && !connection.release_advisory_lock(lock_id)
        raise ActiveRecord::ConcurrentMigrationError.new(
          ActiveRecord::ConcurrentMigrationError::RELEASE_LOCK_FAILED_MESSAGE
        )
      end
    end

    MIGRATOR_SALT = 1942351734

    def generate_migrator_advisory_lock_id
      db_name_hash = Zlib.crc32(ActiveRecord::Base.connection_config[:database])
      MIGRATOR_SALT * db_name_hash
    end
  end

  # based on rails 6.1 AdvisoryLockBase
  class MDAdvisoryLockBase < ActiveRecord::AdvisoryLockBase # :nodoc:
    self.connection_specification_name = "MDAdvisoryLockBase"
  end
end
