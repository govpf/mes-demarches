# frozen_string_literal: true

class Champs::DecimalNumberChamp < Champ
  validates_with NumberLimitValidator, if: :validate_champ_value?
  before_validation :format_value

  validates :value, numericality: {
    allow_nil: true,
    allow_blank: true,
    message: -> (object, _data) {
      object.errors.generate_message(:value, :not_a_number)
    }
  }, format: {
    with: /\A-?[0-9]+([\.,][0-9]{1,3})?\z/,
    allow_nil: true,
    allow_blank: true,
    message: -> (object, _data) {
      # i18n-tasks-use t('errors.messages.not_a_float')
      object.errors.generate_message(:value, :not_a_float)
    }
  }, if: :validate_champ_value?

  validate :min_max_validation, if: :validate_champ_value?

  def min_max_validation
    return if value.blank?

    if type_de_champ.min.present? && value.to_i < type_de_champ.min.to_i
      errors.add(:value, :greater_than_or_equal_to, value: value, count: type_de_champ.min.to_i)
    end
    if type_de_champ.max.present? && value.to_i > type_de_champ.max.to_i
      errors.add(:value, :less_than_or_equal_to, value: value, count: type_de_champ.max.to_i)
    end
  end

  private

  def format_value
    return if value.blank?

    self.value = value.tr(",", ".").gsub(/[[:space:]]/, "")
  end
end
