# frozen_string_literal: true

class FormulaValueDisplayComponent < ApplicationComponent
  include ChampHelper

  def initialize(value:)
    @value = value&.to_s&.strip
  end

  def formatted_value
    return '' if @value.blank?

    if boolean?(@value)
      format_as_boolean(@value)
    elsif url?(@value)
      format_as_url(@value)
    elsif number?(@value)
      format_as_number(@value)
    elsif date?(@value)
      format_as_date(@value)
    else
      format_text_value(@value)
    end
  end

  private

  def boolean?(value)
    value == Champs::BooleanChamp::TRUE_VALUE || value == Champs::BooleanChamp::FALSE_VALUE
  end

  def format_as_boolean(value)
    value == Champs::BooleanChamp::TRUE_VALUE ? t('utils.yes') : t('utils.no')
  end

  def url?(value)
    value.match?(/\Ahttps?:\/\//)
  end

  def date?(value)
    # pf: Date.parse est trop permissif (accepte "Pas validé100" → date).
    # On ne reconnaît que les formats ISO et courants explicites.
    value.match?(/\A\d{4}-\d{2}-\d{2}/) || value.match?(/\A\d{2}\/\d{2}\/\d{4}\z/)
  end

  def number?(value)
    value.match?(/\A-?\d+(\.\d+)?\z/)
  end

  def format_as_url(value)
    link_to(truncate(value, length: 60), value,
            target: '_blank',
            rel: 'noopener noreferrer',
            class: 'fr-link fr-link--external',
            'aria-label': "Lien externe : #{value} (s'ouvre dans un nouvel onglet)")
  end

  def format_as_date(value)
    begin
      parsed_date = Date.parse(value)
      content_tag(:time,
                  l(parsed_date, format: :long),
                  datetime: parsed_date.iso8601,
                  class: 'fr-text')
    rescue ArgumentError
      format_text_value(value)
    end
  end

  def format_as_number(value)
    if value.include?('.')
      number_with_precision(value.to_f, precision: 2, strip_insignificant_zeros: true)
    else
      number_with_delimiter(value.to_i)
    end
  end
end
