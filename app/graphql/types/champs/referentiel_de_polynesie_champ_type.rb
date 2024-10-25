module Types::Champs
  class ReferentielDePolynesieChampType < Types::BaseObject
    implements Types::ChampType

    field :table_id, ID, null: true
    field :search_field, String, null: true
  end
end
