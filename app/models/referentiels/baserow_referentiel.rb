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
  # pf: DLNUF — date (ISO 8601) de la première observation de la table en mode DLNUF sur une
  # démarche publiée. Une fois posée, la perte du mode est refusée (contrat DLNUF §3.4).
  # Remise à zéro : tâche de maintenance uniquement, jamais via Baserow.
  store_accessor :autocomplete_configuration, :dlnuf_vu_le

  scope :pour_table, -> (domain_id) { where(url: "baserow://#{domain_id.to_i}") }

  def self.dlnuf_vu?(domain_id)
    pour_table(domain_id).where("autocomplete_configuration ? 'dlnuf_vu_le'").exists?
  end

  # pf: seulement pour les démarches publiées (ou closes) : en test, le mode reste libre.
  # Sous-requêtes plutôt que joins(revisions: ...), qui aliase types_de_champ.
  def self.memoriser_dlnuf!(domain_id)
    candidats = pour_table(domain_id).where.not("autocomplete_configuration ? 'dlnuf_vu_le'")
    return unless candidats.exists?

    revisions_publiees = ProcedureRevision.where(procedure_id: Procedure.publiees_ou_closes.select(:id))
    tdc_publies = ProcedureRevisionTypeDeChamp.where(revision_id: revisions_publiees.select(:id)).select(:type_de_champ_id)
    referentiel_ids = TypeDeChamp
      .where(id: tdc_publies, referentiel_id: candidats.select(:id))
      .distinct.pluck(:referentiel_id)

    where(id: referentiel_ids).find_each do |referentiel|
      referentiel.dlnuf_vu_le = Time.zone.now.iso8601
      referentiel.update_column(:autocomplete_configuration, referentiel.autocomplete_configuration)
      Rails.logger.info("ReferentielDePolynesie: mode DLNUF mémorisé (référentiel #{referentiel.id}, table #{domain_id})")
    end
  end

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

  # pf: via la façade API pour bénéficier du cache court (l’éditeur de champs appelle ready? par carte)
  def baserow_config
    @baserow_config ||= ReferentielDePolynesie::API.config(table_id)
  end

  # pf: toutes les colonnes de la table (façade avec cache court). Les colonnes méta « Champs usager »
  # et « Champs instructeur » ne sont plus lues : l’affichage passe par referentiel_mapping.
  def headers
    Hash(ReferentielDePolynesie::API.table_fields(table_id)).values.map { _1[:name] }
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
