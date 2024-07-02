class EditableChamp::NumeroDnComponent < EditableChamp::EditableChampBaseComponent
  def input_group_class
    if @champ.numero_dn_success?
      'fr-input-group--valid'
    elsif @champ.numero_dn_error?
      'fr-input-group--error'
    end
  end
end
