class Migrations::BackfillStableIdJob < ApplicationJob
  queue_as :low_priority

  BATCH = 100_000

  def perform(iteration)
    sql = "UPDATE champs SET stable_id = t.stable_id, stream = 'main'
      FROM types_de_champ t
        WHERE champs.type_de_champ_id = t.id
        AND champs.id IN (SELECT id FROM champs WHERE champs.stable_id IS NULL LIMIT ?);"
    query = ActiveRecord::Base.sanitize_sql_array([sql, BATCH])
    ActiveRecord::Base.connection.execute(query)

    if Champ.exists?(stable_id: nil)
      Migrations::BackfillStableIdJob.set(wait: 2.seconds).perform_later(iteration + 1)
    end
  end
end
