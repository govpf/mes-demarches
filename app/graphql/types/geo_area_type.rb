# frozen_string_literal: true

module Types
  module GeoAreaType
    include Types::BaseInterface

    class GeoAreaSource < Types::BaseEnum
      GeoArea.sources.each do |symbol_name, string_name|
        value(string_name,
          I18n.t(symbol_name, scope: [:activerecord, :attributes, :geo_area, :source]),
          value: symbol_name)
      end
    end

    global_id_field :id
    field :source, GeoAreaSource, null: false
    field :geometry, Types::GeoJSON, null: false
    field :description, String, null: true

    definition_methods do
      def resolve_type(object, context)
        case object.source
        when GeoArea.sources.fetch(:cadastre)
          if object.is_building?
            Types::GeoAreas::BatimentType
          else
            Types::GeoAreas::ParcelleCadastraleType
          end
        when GeoArea.sources.fetch(:batiment)
          Types::GeoAreas::BatimentType
        when GeoArea.sources.fetch(:selection_utilisateur)
          if object.champ.class.name == 'Champs::TeFenuaChamp'
            if object.polygon? || object.multipolygon?
              Types::GeoAreas::ZoneType
            else
              Types::GeoAreas::MarqueurType
            end
          else
            Types::GeoAreas::SelectionUtilisateurType
          end
        end
      end
    end
  end
end
