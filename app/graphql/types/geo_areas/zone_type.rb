# frozen_string_literal: true

module Types::GeoAreas
  class ZoneType < MarqueurType
    field :surface, String, null: true
    field :surfaceCalculee, Float, null: true

    def surfaceCalculee
      object.area
    end
  end
end
