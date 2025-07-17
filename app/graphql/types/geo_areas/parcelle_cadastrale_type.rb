# frozen_string_literal: true

module Types::GeoAreas
  class ParcelleCadastraleType < Types::BaseObject
    implements Types::GeoAreaType

    field :numero, String, null: true
    field :section, String, null: true
    field :surface, String, null: true
    field :prefixe, String, null: true
    field :commune, String, null: true
    # pf fields
    field :communeAssociee, String, null: true
    field :ile, String, null: true

    def communeAssociee
      object.commune_associee
    end

    field :code_dep, String, null: false, deprecation_reason: 'Utilisez le champ `commune` à la place.'
    field :nom_com, String, null: false, deprecation_reason: 'Utilisez le champ `commune` à la place.'
    field :code_com, String, null: false, deprecation_reason: 'Utilisez le champ `commune` à la place.'
    field :code_arr, String, null: false, deprecation_reason: 'Utilisez le champ `prefixe` à la place.'
    field :feuille, Int, null: false, deprecation_reason: 'L’information n’est plus disponible.'
    field :surface_intersection, Float, null: false, deprecation_reason: 'L’information n’est plus disponible.'
    field :surface_parcelle, Float, null: false, deprecation_reason: 'Utilisez le champ `surface` à la place.'
  end
end
