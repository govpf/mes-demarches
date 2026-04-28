# frozen_string_literal: true

module Types::Champs::Descriptor
  class FormuleChampDescriptorType < Types::BaseObject
    implements Types::ChampDescriptorType

    field :expression, String, "Expression de la formule avec les libellés des champs référencés", null: true

    def expression
      FormulaExpressionService.convert_to_libelles(
        object.type_de_champ.formule_expression,
        object.revision
      )
    end
  end
end
