# frozen_string_literal: true

class FormulaValueDisplayComponent < ApplicationComponent
  include ChampHelper

  # pf: output_type provient du TypeDeChamp (formule_output_type) et fait foi
  # pour le dispatch de rendu. Le fallback sniffing (output_type: nil) est
  # conservé pour rétrocompat le temps que tous les call-sites passent le type.
  def initialize(value:, output_type: nil)
    @value = value&.to_s&.strip
    @output_type = output_type.presence
  end

  def formatted_value
    return '' if @value.blank?

    case @output_type
    when 'boolean'  then format_as_boolean(@value)
    when 'date'     then format_as_date(@value)
    when 'datetime' then format_as_datetime(@value)
    when 'number'   then format_as_number(@value)
    when 'string'   then format_text_value(@value)
    else
      format_with_sniffing(@value)
    end
  end

  private

  def format_with_sniffing(value)
    if boolean?(value)
      format_as_boolean(value)
    elsif url?(value)
      format_as_url(value)
    elsif number?(value)
      format_as_number(value)
    elsif date?(value)
      format_as_date(value)
    else
      format_text_value(value)
    end
  end

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
    parsed_date = Date.parse(value)
    content_tag(:time,
                l(parsed_date, format: :long),
                datetime: parsed_date.iso8601,
                class: 'fr-text')
  rescue ArgumentError
    format_text_value(value)
  end

  def format_as_datetime(value)
    parsed = Time.zone.parse(value)
    return format_text_value(value) if parsed.nil?

    content_tag(:time,
                l(parsed),
                datetime: parsed.iso8601,
                class: 'fr-text')
  rescue ArgumentError
    format_text_value(value)
  end

  def format_as_number(value)
    # pf: Rational("195/1") → 195.0 ; rescue couvre les strings non-numériques.
    numeric = begin
      Rational(value).to_f
    rescue ArgumentError, TypeError, ZeroDivisionError
      value.to_f
    end

    if numeric == numeric.to_i && !value.include?('.')
      number_with_delimiter(numeric.to_i)
    else
      number_with_precision(numeric, precision: 2, strip_insignificant_zeros: true)
    end
  end
end
