# frozen_string_literal: true

module Types::GeoAreas
  class BatimentType < ZoneType
    implements Types::GeoAreaType

    field :nom, String, null: true

    def nom
      object.nom
    end
  end
end
