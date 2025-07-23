# frozen_string_literal: true

module Types::GeoAreas
  class MarqueurType < Types::BaseObject
    implements Types::GeoAreaType

    field :commune, String, null: true
    field :communeAssociee, String, null: true
    field :ile, String, null: true

    def communeAssociee
      object.commune_associee
    end
  end
end
