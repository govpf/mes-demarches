# frozen_string_literal: true

class TypesDeChampEditor::DuplicateChampButtonComponent < ApplicationComponent
  def initialize(coordinate:, after_stable_id: nil)
    @coordinate = coordinate
    @after_stable_id = after_stable_id
  end

  def render?
    !@coordinate.type_de_champ.repetition? && !@coordinate.child?
  end

  private

  def procedure
    @coordinate.revision.procedure
  end

  def stable_id
    @coordinate.stable_id
  end

  def button_options
    {
      class: "fr-btn fr-btn--tertiary-no-outline fr-icon-file-copy-line",
      method: :post,
      title: "Dupliquer le champ"
    }
  end
end
