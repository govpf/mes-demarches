# frozen_string_literal: true

class EditableChamp::ReferentielDePolynesieComponent < EditableChamp::EditableChampBaseComponent
  include ApplicationHelper
  include Rails.application.routes.url_helpers

  delegate :type_de_champ, to: :@champ
  delegate :referentiel, to: :type_de_champ
  delegate :exact_match?, to: :referentiel, allow_nil: true

  def dsfr_input_classname
    exact_match? ? 'fr-input' : 'fr-select'
  end

  def react_props
    table = @champ.table_id
    react_input_opts(id: @champ.focusable_input_id,
      class: 'fr-mt-1w',
      name: @form.field_name(:external_id),
      selectedKey: @champ.selected,
      items: @champ.selected_items,
      loader: data_sources_rdp_search_path(table:, drop_down_other: @champ.drop_down_other?),
      limit: 20,
      minimumInputLength: 2,
      data: { table_id: @champ.table_id })
  end
end
