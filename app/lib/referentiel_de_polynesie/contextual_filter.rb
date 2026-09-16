# frozen_string_literal: true

# pf: cascade référentiel — résout le champ « pilote » d'un referentiel_de_polynesie filtré,
# construit le filtre Baserow correspondant et compare localement une ligne sélectionnée.
# Point unique de résolution partagé par le endpoint #search (rempart n°1), le composant
# éditable (message d'état vide) et la validation au dépôt (rempart n°2).
# Spec : docs/superpowers/specs/2026-06-17-referentiel-polynesie-filtres-contextuels-design.md
class ReferentielDePolynesie::ContextualFilter
  TEXT_TYPES = ['text', 'long_text', 'email', 'formula'].freeze
  SELECT_TYPES = ['single_select', 'multiple_select'].freeze
  FILTERABLE_BASEROW_TYPES = (TEXT_TYPES + SELECT_TYPES).freeze
  # pf: v1 — pas de :enums (pilote multi-valué : sémantique OU non définie)
  PILOT_COLUMN_TYPES = [:text, :enum].freeze

  attr_reader :type_de_champ, :dossier, :row_id

  def self.for(type_de_champ:, dossier:, row_id: nil)
    new(type_de_champ:, dossier:, row_id:)
  end

  def initialize(type_de_champ:, dossier:, row_id: nil)
    @type_de_champ = type_de_champ
    @dossier = dossier
    @row_id = row_id.presence
  end

  def config
    @config ||= Hash(type_de_champ.referentiel_filter).with_indifferent_access.presence
  end

  def configured? = config.present?

  def baserow_field_id = config&.dig(:baserow_field_id).to_i

  def baserow_field_name = config&.dig(:baserow_field_name).to_s

  # pf: config présente mais inexploitable : colonne pilote inconnue de la procédure, TDC pilote
  # absent de la révision du dossier, pilote dans un bloc qui n'est pas celui du référentiel,
  # ou pilote de la même ligne sans row_id (le champ n'est alors pas projetable : sans ce cas
  # `project_champ` lèverait, au lieu du fail-closed attendu).
  def invalid?
    return false unless configured?
    return true if pilot_column.nil? || baserow_field_id <= 0
    return false unless pilot_column.is_a?(Columns::ChampColumn)

    pilot_tdc.nil? || foreign_block_pilot? || (same_row_pilot? && row_id.blank?)
  end

  def pilot_column
    return @pilot_column if defined?(@pilot_column)

    @pilot_column = find_pilot_column
  end

  def pilot_tdc
    return @pilot_tdc if defined?(@pilot_tdc)

    @pilot_tdc = if pilot_column.is_a?(Columns::ChampColumn)
      dossier.revision.types_de_champ.find { _1.stable_id == pilot_column.stable_id }
    end
  end

  def pilot_libelle
    pilot_tdc&.libelle.presence || pilot_column&.label.to_s
  end

  # pf: valeur du pilote résolue côté serveur (dossier persisté), jamais depuis le client.
  # Pour un pilote de la même ligne de bloc, on projette le champ dans la ligne du référentiel.
  def pilot_value
    return @pilot_value if defined?(@pilot_value)

    @pilot_value = begin
      raw = if invalid? || pilot_column.nil?
        nil
      elsif pilot_column.is_a?(Columns::ChampColumn)
        pilot_column.value(dossier.project_champ(pilot_tdc, row_id: pilot_row_id))
      else
        pilot_column.value(dossier)
      end
      Array.wrap(raw).map { _1.to_s.strip }.compact_blank.first
    end
  end

  # pf: filtre Baserow { field_id:, type:, value: } ou nil (fail-closed : le contrôleur renvoie []).
  # fields : Hash id → { name:, type:, select_options: } (ReferentielDePolynesie::API.table_fields)
  def baserow_scope(fields)
    return nil if pilot_value.blank?

    field = fields&.dig(baserow_field_id)
    return nil if field.nil?

    case field[:type]
    when *TEXT_TYPES
      { field_id: baserow_field_id, type: 'equal', value: pilot_value }
    when *SELECT_TYPES
      option = Array(field[:select_options]).find { _1[:value].to_s.casecmp?(pilot_value) }
      return nil if option.nil?

      { field_id: baserow_field_id, type: field[:type] == 'single_select' ? 'single_select_equal' : 'multiple_select_has', value: option[:id] }
    end
  end

  # pf: comparaison locale (aucun appel Baserow). row_data est le hash plat stocké dans champ.data ;
  # une multiple_select y est simplifiée en « A, B ». Colonne absente → antériorité tolérée.
  def matches_row_data?(row_data)
    return true if row_data.nil? || !row_data.key?(baserow_field_name)

    pilot = pilot_value.to_s
    return false if pilot.blank?

    raw = row_data[baserow_field_name].to_s.strip
    # pf: égalité exacte d'abord : une valeur texte contenant une virgule (« Semences, bio »)
    # est sélectionnable au rempart n°1 (opérateur `equal`) et doit donc rester déposable.
    return true if raw.casecmp?(pilot)

    raw.split(',').map(&:strip).any? { _1.casecmp?(pilot) }
  end

  def empty_label
    if pilot_value.blank?
      I18n.t('shared.champs.referentiel_de_polynesie.filter_pilot_blank', pilot: pilot_libelle)
    else
      I18n.t('shared.champs.referentiel_de_polynesie.filter_no_match', value: pilot_value, pilot: pilot_libelle)
    end
  end

  private

  def find_pilot_column
    return nil unless configured?

    dossier.procedure.find_column(h_id: { procedure_id: dossier.procedure.id, column_id: config[:pilot_column_id].to_s })
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def own_parent_tdc
    return @own_parent_tdc if defined?(@own_parent_tdc)

    @own_parent_tdc = dossier.revision.parent_of(type_de_champ)
  end

  def pilot_parent_tdc
    return @pilot_parent_tdc if defined?(@pilot_parent_tdc)

    @pilot_parent_tdc = pilot_tdc && dossier.revision.parent_of(pilot_tdc)
  end

  def same_row_pilot?
    pilot_parent_tdc.present? && own_parent_tdc.present? && pilot_parent_tdc.stable_id == own_parent_tdc.stable_id
  end

  def foreign_block_pilot?
    pilot_parent_tdc.present? && !same_row_pilot?
  end

  def pilot_row_id
    same_row_pilot? ? row_id : nil
  end
end
