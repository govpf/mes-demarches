# frozen_string_literal: true

class EditableChamp::TableRowSelectorComponent < EditableChamp::EditableChampBaseComponent
  include ApplicationHelper

  def dsfr_input_classname
    'fr-select'
  end

  def react_props
    react_input_opts(id: @champ.input_id,
      class: 'fr-mt-1w',
      name: @form.field_name(:external_id),
      selected_key: @champ.external_id,
      items: @champ.selected_items,
      loader: champs_table_row_selector_search_path,
      limit: 20,
      minimum_input_length: 2,
      data: { table_id: @champ.table_id })
  end
end
