# frozen_string_literal: true

module Types::Champs
  class FormuleChampType < Types::BaseObject
    implements Types::ChampType

    field :value, String, "La valeur calculée de la formule", null: true

    def value
      object.value
    end
  end
end
