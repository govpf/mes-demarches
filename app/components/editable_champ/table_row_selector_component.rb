# frozen_string_literal: true

class EditableChamp::TableRowSelectorComponent < EditableChamp::EditableChampBaseComponent
  include ApplicationHelper
  include Rails.application.routes.url_helpers

  def dsfr_input_classname
    'fr-select'
  end

  def react_props
    table = @champ.table_id
    react_input_opts(id: @champ.input_id,
      class: 'fr-mt-1w',
      name: @form.field_name(:external_id),
      selectedKey: @champ.selected,
      items: @champ.selected_items,
      loader: data_sources_trs_search_path(table:, drop_down_other: @champ.drop_down_other?),
      limit: 20,
      minimumInputLength: 2,
      data: { table_id: @champ.table_id })
  end
end
