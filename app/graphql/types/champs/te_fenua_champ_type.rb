# frozen_string_literal: true

module Types::Champs
  class TeFenuaChampType < Types::BaseObject
    implements Types::ChampType

    field :geo_areas, [Types::GeoAreaType], null: false
    field :parcelles, [Types::GeoAreaType], null: false
    field :batiments, [Types::GeoAreaType], null: false
    field :zones_manuelles, [Types::GeoAreaType], null: false
    field :position, Types::GeoJSON, null: true

    def geo_areas
      Loaders::Association.for(Champs::TeFenuaChamp, :geo_areas).load(object)
    end

    def parcelles
      object.parcelles&.map { |feature| build_geo_area_from_feature(feature) } || []
    end

    def batiments
      object.batiments&.map { |feature| build_geo_area_from_feature(feature) } || []
    end

    def zones_manuelles
      object.zones_manuelles&.map { |feature| build_geo_area_from_feature(feature) } || []
    end

    def position
      object.position
    end

    private

    def build_geo_area_from_feature(feature)
      caller_method = caller_locations(1, 1)[0].label
      source = case caller_method
      when 'parcelles'
        :cadastre
      when 'batiments'
        :batiment
      else
        :selection_utilisateur
      end

      GeoArea.new(
        source: source,
        geometry: feature[:geometry],
        properties: feature[:properties]
      )
    end
  end
end
