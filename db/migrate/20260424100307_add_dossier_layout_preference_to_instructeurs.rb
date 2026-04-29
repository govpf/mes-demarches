# frozen_string_literal: true

class AddDossierLayoutPreferenceToInstructeurs < ActiveRecord::Migration[7.1]
  def change
    add_column :instructeurs, :dossier_layout_preference, :string
  end
end
