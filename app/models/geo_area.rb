# frozen_string_literal: true

class GeoArea < ApplicationRecord
  include ActionView::Helpers::NumberHelper
  belongs_to :champ, optional: false

  # FIXME: once geo_areas are migrated to not use YAML serialization we can enable store_accessor
  # store_accessor :properties, :description, :numero, :section

  def properties
    value = read_attribute(:properties)
    if value.is_a? String
      ActiveRecord::Coders::YAMLColumn.new(:properties).load(value)
    else
      value || {}
    end
  end

  def description
    properties['description']
  end

  def numero
    properties['numero']
  end

  def section
    properties['section']
  end

  def filename
    properties['filename']
  end

  enum :source, {
    cadastre: 'cadastre',
    selection_utilisateur: 'selection_utilisateur'
  }

  scope :selections_utilisateur, -> { where(source: sources.fetch(:selection_utilisateur)) }
  scope :cadastres, -> { where(source: sources.fetch(:cadastre)) }

  validates :geometry, geo_json: true, allow_nil: false

  def to_feature
    {
      type: 'Feature',
      geometry: geometry.deep_symbolize_keys,
      properties: cadastre_properties.merge(
        source: source,
        area: area,
        length: length,
        description: description,
        filename: filename,
        id: id,
        champ_label: champ.libelle,
        champ_id: champ.stable_id,
        champ_row: champ.row_id,
        champ_private: champ.private?,
        dossier_id: champ.dossier_id
      ).compact
    }
  end

  def label
    case source
    when GeoArea.sources.fetch(:cadastre)
      I18n.t("cadastre", scope: 'geo_area.label', numero: numero, prefixe: prefixe, section: section, surface: surface&.round, commune: commune)
    when GeoArea.sources.fetch(:selection_utilisateur)
      if polygon?
        if area > 0
          I18n.t("area", scope: 'geo_area.label', area: number_with_delimiter(area))
        else
          I18n.t("area_unknown", scope: 'geo_area.label')
        end
      elsif line?
        if length > 0
          I18n.t("line", scope: 'geo_area.label', length: number_with_delimiter(length))
        else
          I18n.t("line_unknown", scope: 'geo_area.label')
        end
      elsif point?
        I18n.t("point", scope: 'geo_area.label', location: location)
      end
    end
  end

  def area
    if polygon?
      GeojsonService.area(geometry.deep_symbolize_keys).round(1)
    end
  end

  def length
    if line?
      GeojsonService.length(geometry.deep_symbolize_keys).round(1)
    end
  end

  def location
    if point?
      Geo::Coord.new(*geometry['coordinates'][0..1].reverse).to_s
    end
  end

  def line?
    geometry['type'] == 'LineString'
  end

  def polygon?
    geometry['type'] == 'Polygon'
  end

  def point?
    geometry['type'] == 'Point'
  end

  def legacy_cadastre?
    cadastre? && properties['surface_intersection'].present?
  end

  def cadastre?
    source == GeoArea.sources.fetch(:cadastre)
  end

  def cadastre_properties
    if cadastre?
      {
        cid: cid,
        numero: numero,
        section: section,
        prefixe: prefixe,
        commune: commune,
        surface: surface
      }
    else
      {}
    end
  end

  def code_dep
    if legacy_cadastre?
      properties['code_dep']
    else
      properties['commune']&.[](0..1)
    end
  end

  def code_com
    if legacy_cadastre?
      properties['code_com']
    else
      commune_val = properties['commune']
      commune_val&.[](2...commune_val.size)
    end
  end

  def nom_com
    if legacy_cadastre?
      properties['nom_com']
    else
      ''
    end
  end

  def surface_intersection
    if legacy_cadastre?
      properties['surface_intersection']
    else
      ''
    end
  end

  def feuille
    if legacy_cadastre?
      properties['feuille']
    else
      1
    end
  end

  def code_arr
    prefixe
  end

  def surface_parcelle
    surface
  end

  def surface
    api_surface = if legacy_cadastre?
      properties['surface_parcelle']
    else
      properties['contenance'] || properties['surface']
    end

    # For TeFenua data, extract surface from info_texte if not available in standard fields
    if api_surface.blank? && properties['info_texte'].present?
      match = properties['info_texte'].match(/Surface \(en m²\): (\d+)/)
      api_surface = match[1] if match
    end

    api_surface ? api_surface : area
  end

  def prefixe
    if legacy_cadastre?
      properties['code_arr']
    else
      properties['prefixe'] || ''
    end
  end

  def commune
    if legacy_cadastre?
      "#{properties['code_dep']}#{properties['code_com']}"
    else
      properties['commune']
    end
  end

  # pf ile and commune associee are specific to French polynesia
  def commune_associee
    properties['commune_associee']
  end

  # pf ile and commune associee are specific to French polynesia
  def ile
    properties['ile']
  end

  # Building-specific methods for TeFenua data
  def nom
    properties['nom']
  end

  def info_titre
    properties['info_titre']
  end

  def info_texte
    properties['info_texte']
  end

  def categorie
    properties['categorie']
  end

  def sous_categorie
    properties['sous_categorie']
  end

  def materiau
    properties['materiau']
  end

  def is_building?
    cadastre? && properties['categorie'].present? && !is_parcelle?
  end

  def is_parcelle?
    cadastre? && properties['numero'].present? && properties['section'].present?
  end

  def cid
    if legacy_cadastre?
      "#{code_dep}#{code_com}#{code_arr}#{section}#{numero}"
    else
      properties['id']
    end
  end
end
