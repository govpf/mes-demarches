# frozen_string_literal: true

class Referentiels::BaserowReferentiel < Referentiel
  # pf: le table_id Baserow est stocké dans url au format "baserow://TABLE_ID"
  validates :url, presence: true, format: { with: /\Abaserow:\/\/\d+\z/, message: "doit être au format baserow://TABLE_ID" }

  enum :mode, {
    exact_match: 'exact_match',
    autocomplete: 'autocomplete',
  }

  # pf: nécessaire pour AutocompleteConfigurationComponent qui appelle referentiel.datasource
  # La colonne autocomplete_configuration existe sur tous les référentiels (jsonb)
  store_accessor :autocomplete_configuration, :datasource, :json_template

  def tiptap_template=(value)
    self.json_template = JSON.parse(value)
  end

  def tiptap_template
    json_template&.to_json
  end

  before_save :name_as_uuid

  def table_id
    url&.delete_prefix('baserow://')
  end

  def table_id=(value)
    self.url = value.present? ? "baserow://#{value}" : nil
  end

  def self.csv_available?
    false
  end

  def ready?
    configured? && baserow_config.present?
  end

  def configured?
    mode.present? && table_id.present? && table_id.to_i > 0
  end

  # pf: Baserow gère sa propre UI d'autocomplete via le RDP controller (data_sources_rdp_search_path),
  # l'étape autocomplete_configuration upstream (datasource + json_template) est inutile pour Baserow
  def needs_autocomplete_configuration_step?
    false
  end

  # pf: Baserow gère son auth via BaserowAPI.config, pas via le modèle Referentiel
  def authentication_by_header_token?
    false
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

  # pf: JSONPath plat (plus de $.row. prefix) pour harmoniser avec le format upstream
  def headers_with_path
    headers.map { |h| [h, "$.#{h}"] }
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
