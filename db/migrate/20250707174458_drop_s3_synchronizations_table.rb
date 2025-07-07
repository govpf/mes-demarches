# frozen_string_literal: true

class DropS3SynchronizationsTable < ActiveRecord::Migration[7.0]
  def change
    drop_table :s3_synchronizations, if_exists: true do |t|
      t.bigint "active_storage_blob_id"
      t.boolean "checked"
      t.datetime "created_at", null: false
      t.string "target"
      t.datetime "updated_at", null: false
      t.index ["active_storage_blob_id"], name: "index_s3_synchronizations_on_active_storage_blob_id"
      t.index ["target", "active_storage_blob_id"], name: "index_s3_synchronizations_on_target_and_active_storage_blob_id", unique: true
    end
  end
end
