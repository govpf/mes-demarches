# frozen_string_literal: true

class Referentiels::BaserowReferentiel < Referentiel
  alias_attribute :table_id, :test_data

  validates :table_id, presence: true, numericality: { only_integer: true, greater_than: 0 }

  before_save :name_as_uuid

  def self.csv_available?
    false
  end

  def self.autocomplete_available?
    true
  end

  def ready?
    configured? && baserow_config.present?
  end

  def configured?
    table_id.present? && table_id.to_i > 0
  end

  def url
    "baserow://#{table_id}/{id}"
  end

  def baserow_config
    @baserow_config ||= ReferentielDePolynesie::BaserowAPI.config(table_id)
  end

  def headers
    return [] unless baserow_config

    model = ReferentielDePolynesie::BaserowAPI.fields(baserow_config)
    return [] unless model

    usager_fields = ReferentielDePolynesie::BaserowAPI.field_names(model, baserow_config['Champs usager'])
    instructeur_fields = ReferentielDePolynesie::BaserowAPI.field_names(model, baserow_config['Champs instructeur'])

    (usager_fields + instructeur_fields).uniq
  end

  def headers_with_path
    headers.map { |h| [h, "$.row.#{h}"] }
  end

  def last_response_status
    (last_response || {}).fetch("status") { 500 }
  end

  def last_response_body
    (last_response || {}).fetch("body") { {} }
  end

  private

  def name_as_uuid
    self.name ||= SecureRandom.uuid
  end
end
