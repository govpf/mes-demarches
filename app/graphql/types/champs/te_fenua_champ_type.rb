# frozen_string_literal: true

module Types::Champs
  class TeFenuaChampType < Types::BaseObject
    implements Types::ChampType

    field :geo_areas, [Types::GeoAreaType], null: false
    field :position, Types::GeoJSON, null: true

    def geo_areas
      Loaders::Association.for(Champs::TeFenuaChamp, :geo_areas).load(object)
    end

    def position
      object.position
    end
  end
end
