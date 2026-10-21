# frozen_string_literal: true

class Champs::TeFenuaChamp < Champ
  # We are not using scopes here as we want to access
  # the following collections on unsaved records.
  before_save :strip_html_from_value
  before_save :sync_geo_areas_from_value

  def parcelles
    geo_json_from_value[:parcelles][:features]
  end

  def batiments
    geo_json_from_value[:batiments][:features]
  end

  def zones_manuelles
    geo_json_from_value[:zones_manuelles][:features]
  end

  def parcelles?
    type_de_champ&.parcelles && type_de_champ.parcelles != '0'
  end

  def batiments?
    type_de_champ&.batiments && type_de_champ.batiments != '0'
  end

  def marker?
    type_de_champ && type_de_champ.te_fenua_layer == "marker"
  end

  def zones_manuelles?
    type_de_champ&.zones_manuelles && type_de_champ.zones_manuelles != '0'
  end

  def position
    geo_json_from_value[:position]
  end

  def entry
    result = [];
    if parcelles? then
      result << 'parcelles'
    end
    if batiments? then
      result << 'batiments'
    end
    if zones_manuelles? then
      result << 'zones_manuelles'
    end
    if marker?
      result << 'marker'
    end
    result.join(',')
  end

  def to_render_data
    {
      position: position,
      batiments: batiments? ? batiments : [],
      cadastres: parcelles? ? parcelles : [],
      zones_manuelles: zones_manuelles? ? zones_manuelles : [],
      positions: marker? && geo_areas.present? ? geo_areas.map(&:to_feature) : [],
    }
  end

  def bounding_box
    factory = RGeo::Geographic.simple_mercator_factory
    bounding_box = RGeo::Cartesian::BoundingBox.new(factory)

    if geo_areas.present?
      geo_areas.map(&:rgeo_geometry).compact.each do |geometry|
        bounding_box.add(geometry)
      end
    elsif dossier.present?
      point = dossier.geo_position
      bounding_box.add(factory.point(point[:lon], point[:lat]))
    else
      bounding_box.add(factory.point(DEFAULT_LON, DEFAULT_LAT))
    end

    [bounding_box.max_point, bounding_box.min_point].compact.flat_map(&:coordinates)
  end

  def to_feature_collection
    {
      type: 'FeatureCollection',
      id: stable_id,
      bbox: bounding_box,
      features: geo_areas.map(&:to_feature),
    }
  end

  def geo_json_from_value
    @geo_json_from_value ||= begin
      parsed_value = value.blank? ? nil : JSON.parse(value, symbolize_names: true)
      # We used to store in the value column a json array with coordinates.
      if parsed_value.is_a?(Array)
        # Empty array is sent instead of blank to distinguish between empty and error
        if parsed_value.empty?
          nil
        else
          # If it is a coordinates array, format it as a GEO-JSON
          JSON.parse(GeojsonService.to_json_polygon_for_selection_utilisateur(parsed_value))
        end
      else
        # It is already a GEO-JSON
        parsed_value
      end
    end
  end

  def for_api
    nil
  end

  private

  HTML_CHARS = /[<>]/

  # La valeur est un GeoJSON fourni tel quel par le navigateur de l'usager puis
  # réaffiché chez l'instructeur : on retire les chevrons des identifiants et des
  # propriétés pour qu'aucune balise ne puisse y être injectée.
  # Le JSON est toujours décodé : un chevron peut y être écrit "<".
  def strip_html_from_value
    return unless value_changed? && value.present?

    parsed_value = JSON.parse(value)
    stripped_value = strip_html(parsed_value)
    self.value = stripped_value.to_json if stripped_value != parsed_value
  rescue JSON::ParserError
    nil
  end

  def strip_html(object)
    case object
    when Hash then object.transform_values { strip_html(it) }
    when Array then object.map { strip_html(it) }
    when String then object.gsub(HTML_CHARS, '')
    else object
    end
  end

  def sync_geo_areas_from_value
    return unless value_changed? && value.present?

    parsed_data = begin
      JSON.parse(value, symbolize_names: true)
                  rescue JSON::ParserError
                    Rails.logger.error("Failed to parse JSON for Champs::TeFenuaChamp #{id} from value: #{value}")
                    return
    end

    geo_areas.destroy_all

    source = GeoArea.sources.fetch(:selection_utilisateur);
    parsed_data.each do |category, collection|
      next if category == :positions

      collection[:features].each do |feature|
        geo_areas.build(source:, geometry: feature[:geometry], properties: feature[:properties]&.reject { |k, _v| k == :style })
      end
    end
  end
end
