# frozen_string_literal: true

module Types::GeoAreas
  class BatimentType < Types::BaseObject
    implements Types::GeoAreaType

    field :nom, String, null: true
    field :infoTitre, String, null: true
    field :infoTexte, String, null: true
    field :categorie, String, null: true
    field :sousCategorie, String, null: true
    field :materiau, String, null: true
    field :surfaceCalculee, Float, null: true

    def infoTitre
      object.info_titre
    end

    def infoTexte
      object.info_texte
    end

    def sousCategorie
      object.sous_categorie
    end

    def surfaceCalculee
      object.area
    end
  end
end
