# frozen_string_literal: true

class Champs::TableRowSelectorChamp < Champs::TextChamp
  def fetch_external_data?
    true
  end

  def fetch_external_data
    TableRowSelector::API.fetch_row(external_id)
  end

  def update_with_external_data!(data:)
    update!(data: data) if data&.is_a?(Hash)
  end

  def selected
    external_id
  end

  def selected_items
    if external_id.present? && value.present?
      [{ label: value, value: external_id }]
    else
      []
    end
  end

  def value
    external_id
  end
end
