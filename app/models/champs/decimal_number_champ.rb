class Champs::DecimalNumberChamp < Champ
  before_validation :format_value
  validates :value, numericality: {
    allow_nil: true,
    allow_blank: true
  }
  validate :min_max_validation

  def min_max_validation
    return if value.blank?

    if type_de_champ.min.present? && value.to_i < type_de_champ.min.to_i
      errors.add(:value, :greater_than_or_equal_to, value: value, count: type_de_champ.min.to_i)
    end
    if type_de_champ.max.present? && value.to_i > type_de_champ.max.to_i
      errors.add(:value, :less_than_or_equal_to, value: value, count: type_de_champ.max.to_i)
    end
  end

  def for_export
    processed_value
  end

  def for_api
    processed_value
  end

  private

  def format_value
    return if value.blank?

    self.value = value.tr(",", ".")
  end

  def processed_value
    return if invalid?

    value&.to_f
  end
end
