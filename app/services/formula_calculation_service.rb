# frozen_string_literal: true

class FormulaCalculationService
  class CircularReferenceError < StandardError; end
  class InvalidFieldReferenceError < StandardError; end
  class CalculationError < StandardError; end

  def initialize(dossier, locale: I18n.locale)
    @dossier = dossier
    @locale = locale
    @calculator = create_calculator
  end

  def compute_value(formule_champ)
    return '' if formule_champ.type_de_champ.formule_expression.blank?

    expression = formule_champ.type_de_champ.formule_expression

    # Detect circular references
    detect_circular_references(formule_champ, expression)

    # Resolve field references using labels
    resolved_expression = resolve_field_references(expression)

    # Calculate with Dentaku
    result = @calculator.evaluate(resolved_expression)

    # Format result
    format_result(result)
  rescue CircularReferenceError
    "Erreur : référence circulaire détectée"
  rescue InvalidFieldReferenceError => e
    "Erreur : champ '#{e.message}' introuvable"
  rescue Dentaku::ParseError => e
    "Erreur de syntaxe : #{e.message}"
  rescue Dentaku::UnboundVariableError => e
    "Erreur : variable '#{e.unbound_variable}' non définie"
  rescue StandardError => e
    "Erreur de calcul : #{e.message}"
  end

  private

  def create_calculator
    calculator = Dentaku::Calculator.new

    # Add French function aliases if locale is French
    if @locale.to_s.start_with?('fr')
      add_french_functions(calculator)
    end

    calculator
  end

  def add_french_functions(calculator)
    # Add French aliases for common Excel functions
    calculator.add_function(:SOMME, :numeric, -> (values) { values.sum })
    calculator.add_function(:MOYENNE, :numeric, -> (values) { values.sum.to_f / values.length })
    calculator.add_function(:SI, :numeric, -> (condition, true_value, false_value) {
      condition ? true_value : false_value
    })
    calculator.add_function(:MIN, :numeric, -> (values) { values.min })
    calculator.add_function(:MAX, :numeric, -> (values) { values.max })
    calculator.add_function(:ABS, :numeric, -> (value) { value.abs })
    calculator.add_function(:ARRONDI, :numeric, -> (value, precision = 0) { value.round(precision) })
  end

  def detect_circular_references(formule_champ, expression, visited = Set.new)
    champ_label = formule_champ.libelle

    if visited.include?(champ_label)
      raise CircularReferenceError, "Référence circulaire détectée"
    end

    visited.add(champ_label)

    # Extract field references from expression
    field_references = extract_field_references(expression)

    field_references.each do |field_label|
      referenced_champ = find_champ_by_label(field_label)
      next unless referenced_champ&.type_champ == 'formule'

      # Recursively check for circular references
      detect_circular_references(
        referenced_champ,
        referenced_champ.type_de_champ.formule_expression,
        visited.dup
      )
    end
  end

  def resolve_field_references(expression)
    # Replace {Field Label} patterns with actual values
    expression.gsub(/\{([^}]+)\}/) do |_match|
      field_label = $1.strip
      champ = find_champ_by_label(field_label)

      if champ.nil?
        raise InvalidFieldReferenceError, field_label
      end

      get_champ_numeric_value(champ)
    end
  end

  def extract_field_references(expression)
    expression.scan(/\{([^}]+)\}/).map { |match| match[0].strip }
  end

  def find_champ_by_label(label)
    # Find champ by matching the libelle from the type_de_champ
    @dossier.champs.find do |champ|
      champ.libelle&.strip&.casecmp?(label.strip)
    end
  end

  def get_champ_numeric_value(champ)
    case champ.type_champ
    when 'integer_number'
      champ.value.present? ? champ.value.to_i : 0
    when 'number', 'decimal_number'
      champ.value.present? ? champ.value.to_f : 0
    when 'yes_no'
      champ.value == 'true' ? 1 : 0
    when 'checkbox'
      champ.value == 'on' ? 1 : 0
    when 'formule'
      # Recursive calculation for formula fields
      result = compute_value(champ)
      result.is_a?(String) && result.match?(/\A-?\d+(\.\d+)?\z/) ? result.to_f : 0
    when 'date'
      # Convert date to days since epoch for calculations
      champ.value.present? ? Date.parse(champ.value).to_time.to_i / (24 * 3600) : 0
    when 'datetime'
      # Convert datetime to timestamp for calculations
      champ.value.present? ? DateTime.parse(champ.value).to_time.to_i : 0
    when 'drop_down_list', 'multiple_drop_down_list'
      # Try to extract numbers from dropdown values
      extract_number_from_text(champ.value)
    else
      # For text fields, try to extract numbers
      extract_number_from_text(champ.value)
    end
  rescue StandardError
    0
  end

  def extract_number_from_text(text)
    return 0 if text.blank?

    # Try to find a number in the text
    number_match = text.to_s.match(/-?\d+(?:[.,]\d+)?/)
    return 0 unless number_match

    # Handle French decimal separator (comma)
    number_string = number_match[0].tr(',', '.')
    number_string.to_f
  end

  def format_result(result)
    case result
    when Integer
      result.to_s
    when Float
      # Remove unnecessary decimal places
      result % 1 == 0 ? result.to_i.to_s : result.round(10).to_s.sub(/\.?0+$/, '')
    when TrueClass, FalseClass
      result ? '1' : '0'
    else
      result.to_s
    end
  end
end
