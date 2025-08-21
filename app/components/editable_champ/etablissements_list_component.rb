# frozen_string_literal: true

class EditableChamp::EtablissementsListComponent < ApplicationComponent
  def initialize(etablissements:, input_id:, siret_prefix: nil)
    @etablissements = etablissements
    @input_id = input_id
    @siret_prefix = siret_prefix
  end
end
