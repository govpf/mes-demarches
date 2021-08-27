namespace :swarm do
  desc 'Run migrations tasks after acquisition of lock on database'
  task migrate: :environment do
    result = 1
    (1..10).each do |i|
      Swarm::Migration.new.migrate("Context #{i}:")
      puts "Attempt #{i} sucessfully terminated"
      result = 0
      break
    rescue ActiveRecord::ConcurrentMigrationError
      seconds = rand(3..10)
      puts "Attempt #{i} another migration is running => sleeping #{seconds}s"
      sleep(seconds)
    rescue => e
      puts e
      e.backtrace.each { |m| puts m }
      break
    end
    exit(result)
  end
end
