# frozen_string_literal: true

class Champs::ReferentielDePolynesieChamp < Champs::ReferentielChamp
  # pf: préserver le label humain dans value (upstream y met external_id)
  def clear_previous_result
    self.data = nil
    self.value_json = nil
    self.fetch_external_data_exceptions = []
  end

  # pf: override pour calculer value_json tout en préservant le label dans value
  def update_external_data!(data:)
    transaction do
      update!(
        data:,
        value_json: cast_displayable_values(data.with_indifferent_access),
        fetch_external_data_exceptions: []
      )
      propagate_prefill(data)
    end
  end

  # pf: fallback legacy si pas encore de referentiel lié
  def fetch_external_data
    referentiel.present? ? super : fetch_external_data_legacy
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

  # pf: dual-mode — normalise les données entre ancien format (avec row) et nouveau format (plat)
  def normalized_data
    if data&.key?('row')
      data['row'] # ancien format
    else
      data # nouveau format plat
    end
  end

  # pf: support colonnes pour tags/exports (dual-mode)
  def referentiel_item_value(path)
    normalized_data&.dig(path.to_s)
  end

  # pf: pour les ancres d'erreur (#11420), le React ComboBox utilise html_id sans suffixe -input
  def focusable_input_id(attribute = :value)
    html_id
  end

  private

  def fetch_external_data_legacy
    result = ReferentielDePolynesie::API.fetch_row(external_id)

    if result.present? && result.is_a?(Hash) && result.keys.any?
      Dry::Monads::Success(result.with_indifferent_access)
    else
      Dry::Monads::Failure(retryable: false, reason: StandardError.new('Row not found'), code: 404)
    end
  rescue StandardError => e
    Rails.logger.error("ReferentielDePolynesieChamp fetch error: #{e.class} - #{e.message}")
    Dry::Monads::Failure(retryable: false, reason: e, code: 500)
  end
end
