# frozen_string_literal: true

class AddDeletionEmailNotificationsEnabledToAssignTos < ActiveRecord::Migration[7.0]
  def change
    add_column :assign_tos, :deletion_email_notifications_enabled, :boolean, default: true, null: false
  end
end
