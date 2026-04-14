# frozen_string_literal: true

class EditableChamp::FormuleComponent < EditableChamp::EditableChampBaseComponent
  delegate :type_de_champ, to: :@champ

  def dsfr_champ_container
    :div
  end

  def formatted_value
    return '' if @champ.value.blank?

    render FormulaValueDisplayComponent.new(value: @champ.value)
  end
end
