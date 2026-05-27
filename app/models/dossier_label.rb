# frozen_string_literal: true

class DossierLabel < ApplicationRecord
  belongs_to :dossier
  belongs_to :label

  validate :label_belongs_to_dossier_procedure

  private

  def label_belongs_to_dossier_procedure
    return if dossier.nil? || label.nil?

    if label.procedure_id != dossier.procedure&.id
      errors.add(:label, :invalid)
    end
  end
end
