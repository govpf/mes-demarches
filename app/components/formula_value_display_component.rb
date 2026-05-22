# frozen_string_literal: true

class FormulaValueDisplayComponent < ApplicationComponent
  include ChampHelper

  # pf: On reçoit le champ entier (pas value + output_type séparés) pour
  # garantir une source unique de vérité au call-site : un dev ne peut pas
  # oublier de passer le type tout en passant la valeur.
  # formule_output_type est inféré dans FormuleTypeDeChamp#validate_expression
  # à chaque save — tout TDC formule validé en base a donc un type non-nil.
  def initialize(champ:)
    @value = champ.value&.to_s&.strip
    @output_type = champ.type_de_champ.formule_output_type
  end

  def formatted_value
    return '' if @value.blank?

    case @output_type
    when 'boolean'  then format_as_boolean(@value)
    when 'date'     then format_as_date(@value)
    when 'datetime' then format_as_datetime(@value)
    when 'number'   then format_as_number(@value)
    else # 'string' ou nil (défensif) → texte brut, jamais de sniffing
      format_text_value(@value)
    end
  end

  private

  def format_as_boolean(value)
    value == Champs::BooleanChamp::TRUE_VALUE ? t('utils.yes') : t('utils.no')
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

  # pf: Rational("195/1") → 195.0 ; rescue couvre les strings non-numériques.
  def format_as_number(value)
    numeric = parse_numeric(value)

    if numeric == numeric.to_i && !value.include?('.')
      number_with_delimiter(numeric.to_i)
    else
      number_with_precision(numeric, precision: 2, strip_insignificant_zeros: true)
    end
  end

  def parse_numeric(value)
    Rational(value).to_f
  rescue ArgumentError, TypeError, ZeroDivisionError
    value.to_f
  end
end
