# frozen_string_literal: true

class Champs::DateChamp < Champ
  validates_with DateLimitValidator, if: :validate_champ_value?
  before_validation :convert_to_iso8601_date, unless: -> { validation_context == :prefill }
  validate :iso_8601
  validate :min_max_validation, if: :validate_champ_value?

  def min_max_validation
    return if value.blank?

    if type_de_champ.min.present? && Date.parse(value) < Date.parse(type_de_champ.min)
      errors.add(:value, :greater_than_or_equal_to, value: value, count: I18n.l(Date.parse(type_de_champ.min), format: :long))
    end
    if type_de_champ.max.present? && Date.parse(value) > Date.parse(type_de_champ.max)
      errors.add(:value, :less_than_or_equal_to, value: value, count: I18n.l(Date.parse(type_de_champ.max), format: :long))
    end
  end

  def search_terms
    # Text search is pretty useless for dates so we’re not including these champs
  end

  def formatted_value
    LexpolFieldsService.format_date(value)
  end

  private

  def convert_to_iso8601_date
    self.value = DateDetectionUtils.convert_to_iso8601_date(value)
  end

  def iso_8601
    return if DateDetectionUtils.parsable_iso8601_date?(value) || value.blank?

    # i18n-tasks-use t('errors.messages.not_a_date')
    errors.add :date, :not_a_date
  end
end
