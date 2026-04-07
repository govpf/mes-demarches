
# frozen_string_literal: true

class FormulaCalculationService
  class CircularReferenceError < StandardError; end
  class InvalidFieldReferenceError < StandardError; end
  class CalculationError < StandardError; end

  # pf: value_overrides permet de passer des valeurs fraîchement calculées
  # pour la transitivité (A → B → C) sans dépendre du cache AR du dossier.
  # Hash { stable_id => value_string }
  def initialize(dossier, locale: I18n.locale, value_overrides: {})
    @dossier = dossier
    @locale = locale
    @calculator = create_calculator
    @procedure = dossier.procedure
    @revision = dossier.revision
    @value_overrides = value_overrides
  end

  def compute_value(formule_champ)
    return '' if formule_champ.type_de_champ.formule_expression.blank?

    expression = formule_champ.type_de_champ.formule_expression
    @formula_champ = formule_champ
    @row_id = formule_champ.row_id
    @resolver = FormulaColumnResolver.new(@revision, row_id: @row_id)

    # Detect circular references
    detect_circular_references(formule_champ, expression)

    # Resolve field references using columns
    resolved_expression = resolve_column_references(expression)

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

  # pf: Crée un calculator Dentaku avec les fonctions FR, utilisable
  # pour la validation syntaxique sans instancier le service complet.
  def self.new_calculator(locale: I18n.locale)
    calculator = Dentaku::Calculator.new
    new_instance = allocate
    new_instance.send(:add_french_functions, calculator) if locale.to_s.start_with?('fr')
    calculator
  end

  private

  def create_calculator
    calculator = Dentaku::Calculator.new

    if @locale.to_s.start_with?('fr')
      add_french_functions(calculator)
    end

    calculator
  end

  def add_french_functions(calculator)
    # Add French aliases for common Excel functions
    # Support both array and variadic arguments: SOMME(1, 2, 3) and SOMME([1, 2, 3])
    calculator.add_function(:SOMME, :numeric, -> (*args) { args.flatten.sum })
    calculator.add_function(:MOYENNE, :numeric, -> (*args) {
      values = args.flatten
      values.sum.to_f / values.length
    })
    calculator.add_function(:SI, :numeric, -> (condition, true_value, false_value) {
      # Treat 0, false, nil, and empty string as false (Excel-like behavior)
      truthy = case condition
      when nil, false, '', 0, 0.0
        false
      else
        true
      end
      truthy ? true_value : false_value
    })
    calculator.add_function(:MIN, :numeric, -> (*args) { args.flatten.min })
    calculator.add_function(:MAX, :numeric, -> (*args) { args.flatten.max })
    calculator.add_function(:ABS, :numeric, -> (value) { value.abs })
    calculator.add_function(:ARRONDI, :numeric, -> (value, precision = 0) { value.round(precision) })

    # Add French aliases for logical operators (Excel-compatible syntax)
    calculator.add_function(:ET, :logical, -> (*args) {
      if args.empty?
        raise Dentaku::ArgumentError, 'ET() nécessite au moins un argument'
      end
      args.all? { |arg| arg == true || (arg != false && arg != nil && arg != 0 && arg != '') }
    })
    calculator.add_function(:OU, :logical, -> (*args) {
      if args.empty?
        raise Dentaku::ArgumentError, 'OU() nécessite au moins un argument'
      end
      args.any? { |arg| arg == true || (arg != false && arg != nil && arg != 0 && arg != '') }
    })
    calculator.add_function(:NON, :logical, -> (value) {
      !(value == true || (value != false && value != nil && value != 0 && value != ''))
    })

    # pf: French aliases for text functions
    calculator.add_function(:CONCATENER, :string, -> (*args) { args.flatten.map(&:to_s).join })
    calculator.add_function(:GAUCHE, :string, -> (text, n) { text.to_s[0, n.to_i] })
    calculator.add_function(:DROITE, :string, -> (text, n) { text.to_s[(-n.to_i)..] || '' })
    calculator.add_function(:STXT, :string, -> (text, start, n) { text.to_s[(start.to_i - 1), n.to_i] || '' })
    calculator.add_function(:NBCAR, :numeric, -> (text) { text.to_s.length })
    calculator.add_function(:CHERCHE, :numeric, -> (search, text, start = 1) {
      pos = text.to_s.downcase.index(search.to_s.downcase, start.to_i - 1)
      pos ? pos + 1 : 0
    })
    calculator.add_function(:SUBSTITUE, :string, -> (text, old_str, new_str) {
      text.to_s.gsub(old_str.to_s, new_str.to_s)
    })
    calculator.add_function(:MAJUSCULE, :string, -> (text) { text.to_s.upcase })
    calculator.add_function(:MINUSCULE, :string, -> (text) { text.to_s.downcase })
    calculator.add_function(:SUPPRESPACE, :string, -> (text) { text.to_s.strip.gsub(/\s+/, ' ') })
  end

  def detect_circular_references(formule_champ, expression, visited = Set.new)
    champ_stable_id = formule_champ.stable_id

    if visited.include?(champ_stable_id)
      raise CircularReferenceError, "Référence circulaire détectée"
    end

    visited.add(champ_stable_id)

    # Extract field references from expression (now stable_ids)
    field_references = extract_field_references(expression)

    field_references.each do |stable_id|
      referenced_champ = find_champ_by_stable_id(stable_id)
      next unless referenced_champ&.formule?

      # Recursively check for circular references
      detect_circular_references(
        referenced_champ,
        referenced_champ.type_de_champ.formule_expression,
        visited.dup
      )
    end
  end

  def resolve_field_references(expression)
    # Old method kept for backward compatibility
    # Replace {stable_id} patterns with actual values
    expression.gsub(/\{([^}]+)\}/) do |_match|
      stable_id_str = $1.strip

      # Try to parse as stable_id (integer), fallback to label for backward compatibility
      if /^\d+$/.match?(stable_id_str)
        champ = find_champ_by_stable_id(stable_id_str.to_i)
        if champ.nil?
          raise InvalidFieldReferenceError, "Champ ##{stable_id_str}"
        end
      else
        # Fallback for old expressions using labels
        champ = find_champ_by_label(stable_id_str)
        if champ.nil?
          raise InvalidFieldReferenceError, stable_id_str
        end
      end

      get_champ_numeric_value(champ)
    end
  end

  def resolve_column_references(expression)
    # New method using FormulaColumnResolver for column-based formulas
    # Supports: {tdc456}, {dossier_number}, {tdc456/date_de_naissance}, etc.
    expression.gsub(/\{([^}]+)\}/) do |_match|
      reference = $1.strip

      # For backward compatibility: if it's a plain number, treat as stable_id
      if /^\d+$/.match?(reference)
        champ = find_champ_by_stable_id_and_row(reference.to_i, @row_id)
        if champ.nil?
          raise InvalidFieldReferenceError, "Champ ##{reference}"
        end
        next get_champ_numeric_value(champ)
      end

      # New column-based resolution
      column, path = @resolver.resolve_with_path(reference)

      if column.nil?
        raise InvalidFieldReferenceError, reference
      end

      value = extract_column_value(column, path)
      format_value_for_dentaku(value, column.type)
    end
  end

  def extract_column_value(column, path)
    if column.dossier_column?
      column.value(@dossier)
    elsif column.champ_column?
      # pf: Prioriser les value_overrides pour la transitivité
      if path == :value && @value_overrides.key?(column.stable_id)
        return @value_overrides[column.stable_id]
      end

      champ = find_champ_by_stable_id_and_row(column.stable_id, @row_id)

      if champ.nil?
        return nil
      end

      if path == :value
        column.value(champ)
      else
        # Sub-property (DN date_de_naissance, referentiel/Commune, etc.)
        # Use the column's typed_value to extract the JSON path
        if column.is_a?(Columns::JSONPathColumn)
          column.send(:typed_value, champ)
        elsif column.is_a?(Columns::LinkedDropDownColumn)
          column.value(champ)
        else
          nil
        end
      end
    else
      nil
    end
  end

  def format_value_for_dentaku(value, type)
    case type
    when :integer
      value.present? ? value.to_i : 0
    when :decimal
      value.present? ? value.to_f : 0
    when :boolean
      value ? 1 : 0
    when :date, :datetime
      # Convert to timestamp for calculations
      value.present? ? value.to_time.to_i : 0
    when :enum
      # Try to extract number from enum value
      extract_number_from_text(value)
    else
      # Text or unknown: try to extract number
      extract_number_from_text(value)
    end
  rescue StandardError
    0
  end

  def extract_field_references(expression)
    expression.scan(/\{([^}]+)\}/).filter_map do |match|
      ref = match[0].strip
      # pf: Support both {123} (old) and {tdc123} / {tdc123/path} (new) formats
      if /^\d+$/.match?(ref)
        ref.to_i
      elsif ref.match?(/^tdc(\d+)/)
        ref.match(/^tdc(\d+)/)[1].to_i
      end
      # System columns (dossier_*, individual_*) are ignored for circular reference detection
    end
  end

  def find_champ_by_label(label)
    # Find champ by matching the libelle from the type_de_champ
    # pf: use project_champs to avoid duplicates from different streams/revisions
    all_champs.find do |champ|
      champ.libelle&.strip&.casecmp?(label.strip)
    end
  end

  def find_champ_by_stable_id(stable_id)
    # Find champ by stable_id (more robust than label matching)
    # pf: use project_champs to avoid duplicates from different streams/revisions
    all_champs.find { |champ| champ.stable_id == stable_id }
  end

  def find_champ_by_stable_id_and_row(stable_id, row_id)
    # Find champ with automatic precedence: current row first, then parent fallback
    # Optimized to avoid double scan when row_id == nil
    champ_in_row = all_champs.find { |c| c.stable_id == stable_id && c.row_id == row_id }
    return champ_in_row if champ_in_row || row_id.nil?

    # Fallback: search in parent fields (row_id == nil)
    all_champs.find { |c| c.stable_id == stable_id && c.row_id.nil? }
  end

  def all_champs
    # Get all champs (public + private) including repetition rows, without duplicates
    # This ensures formulas work correctly with the current revision and stream
    @all_champs ||= (@dossier.project_champs_public_all + @dossier.project_champs_private_all)
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
    when Float, BigDecimal
      # Si pas de partie décimale, convertir en entier
      if result % 1 == 0
        result.to_i.to_s
      else
        # Enlever les zéros inutiles à la fin
        result.to_s.sub(/\.?0+$/, '')
      end
    when TrueClass, FalseClass
      result ? '1' : '0'
    else
      result.to_s
    end
  end
end
