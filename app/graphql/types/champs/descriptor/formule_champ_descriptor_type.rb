# frozen_string_literal: true

module Types::Champs::Descriptor
  class FormuleChampDescriptorType < Types::BaseObject
    implements Types::ChampDescriptorType

    field :expression, String, "Expression de la formule", null: true

    def expression
      object.type_de_champ.formule_expression
    end
  end
end