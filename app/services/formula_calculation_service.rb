
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
    # pf: valeurs passées à Dentaku comme variables plutôt qu'injectées dans
    # la chaîne d'expression — évite tout problème d'échappement (guillemets,
    # backslashes) dans les champs texte.
    @variables = {}
    @var_counter = 0

    # Detect circular references
    detect_circular_references(formule_champ, expression)

    # Resolve field references using columns
    resolved_expression = resolve_column_references(expression)

    # Calculate with Dentaku
    result = @calculator.evaluate(resolved_expression, @variables)

    # Format result
    format_result(result)
  rescue CircularReferenceError
    "Erreur : référence circulaire détectée"
  rescue InvalidFieldReferenceError => e
    "Erreur : champ '#{e.message}' introuvable"
  rescue Dentaku::ParseError, Dentaku::TokenizerError => e
    "Erreur de syntaxe : #{self.class.translate_error(e)}"
  rescue Dentaku::UnboundVariableError => e
    self.class.translate_error(e)
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

  # pf: Traduit une exception Dentaku en message utilisateur français.
  # Dentaku ne supporte pas l'i18n (messages hardcodés en anglais), on
  # utilise l'attribut `reason` et `meta` des exceptions pour construire
  # un message traduisible via I18n.
  def self.translate_error(exception)
    case exception
    when Dentaku::ParseError
      I18n.t("formula_errors.parse.#{exception.reason}",
             **sanitize_meta(exception.meta),
             default: exception.message)
    when Dentaku::TokenizerError
      I18n.t("formula_errors.tokenizer.#{exception.reason}",
             **sanitize_meta(exception.meta),
             default: exception.message)
    when Dentaku::UnboundVariableError
      I18n.t('formula_errors.unbound_variable',
             variable: exception.unbound_variables.join(', '),
             default: exception.message)
    else
      I18n.t('formula_errors.generic', message: exception.message)
    end
  end

  # pf: Rend les métadonnées de l'exception Dentaku lisibles par un humain.
  # En particulier, `meta[:operator]` contient la classe AST interne
  # (ex: Dentaku::AST::Addition, ou une classe anonyme pour les fonctions
  # personnalisées). L'interpolation directe donne "#<Class:0x...>" ou
  # "Dentaku::AST::Multiplication" — pas parlant pour l'utilisateur.
  def self.sanitize_meta(meta)
    meta.transform_values do |value|
      if value.is_a?(Class) && value < Dentaku::AST::Node
        format_operator(value)
      else
        value
      end
    end
  end

  # pf: Formate une classe d'opérateur Dentaku en chaîne lisible.
  # Fonctions custom (SI, SOMME, CONCATENER...) → leur nom en majuscules.
  # Opérateurs arithmétiques → symbole correspondant (+, -, *, /, ...).
  # Fallback → nom de la classe sans le préfixe Dentaku::AST::.
  OPERATOR_SYMBOLS = {
    'Addition' => '+',
    'Subtraction' => '-',
    'Multiplication' => '*',
    'Division' => '/',
    'Modulo' => '%',
    'Exponentiation' => '^',
    'Negation' => '-',
    'LessThan' => '<',
    'LessThanOrEqual' => '<=',
    'GreaterThan' => '>',
    'GreaterThanOrEqual' => '>=',
    'Equal' => '==',
    'NotEqual' => '!=',
    'And' => 'ET',
    'Or' => 'OU',
    'Not' => 'NON',
  }.freeze

  def self.format_operator(klass)
    # Fonction custom (SOMME, SI, CONCATENER, ...) : klass.name est un Symbol
    # ex: :SI → "SI"
    return klass.name.to_s.upcase if klass.name.is_a?(Symbol)

    name = klass.name.to_s
    # Opérateur built-in : Dentaku::AST::Addition → "+"
    short = name.sub('Dentaku::AST::', '')
    OPERATOR_SYMBOLS[short] || short
  end

  # pf: Détecte l'usage du signe '=' seul (confusion fréquente avec '==').
  # Retourne un message d'aide ciblé, ou nil si pas ce cas.
  def self.detect_equals_operator_hint(expression)
    return nil if expression.blank?
    # Match '=' qui n'est pas précédé ni suivi de '=', '<', '>', '!'
    if expression.match?(/(?<![=<>!])=(?!=)/)
      I18n.t('formula_errors.equals_operator_hint')
    end
  end

  # pf: Pattern de détection des fonctions qui dépendent de l'instant présent
  # (i.e. qui renvoient une valeur différente au fil du temps sans qu'aucun
  # champ source n'ait changé). Utilisé par le TDC pour marquer la formule,
  # et par RefreshFormulasJob pour cibler les formules à recalculer à minuit.
  # AGE/EST_PASSEE/EST_FUTURE dépendent implicitement de Date.current.
  # JOUR/MOIS/ANNEE/JOURSEM ne sont PAS clock-dependent (dépendent uniquement
  # de leur argument).
  CLOCK_DEPENDENT_PATTERN = /\b(AUJOURDHUI|MAINTENANT|AGE|EST_PASSEE|EST_FUTURE)\s*\(/

  def self.clock_dependent?(expression)
    return false if expression.blank?
    expression.match?(CLOCK_DEPENDENT_PATTERN)
  end

  # pf: Pattern de détection des références aux timestamps d'état du dossier.
  # Ces valeurs changent à chaque transition (depose_at au dépôt,
  # en_instruction_at au passage en instruction, etc.), et nécessitent donc
  # un recalcul synchrone au moment de la transition — le job quotidien
  # créerait un lag max 24h inacceptable pour des formules type "jours en
  # instruction".
  STATE_DEPENDENT_PATTERN = /\{dossier_(depose|en_construction|en_instruction|processed)_at\}/

  def self.state_dependent?(expression)
    return false if expression.blank?
    expression.match?(STATE_DEPENDENT_PATTERN)
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

    # pf: conversion explicite texte → nombre (équivalent VALUE/CNUM d'Excel).
    # Gère le séparateur décimal français (virgule) et retourne 0 si non parsable.
    calculator.add_function(:VALEUR, :numeric, -> (text) {
      str = text.to_s.strip
      return 0 if str.empty?
      match = str.match(/-?\d+(?:[.,]\d+)?/)
      match ? match[0].tr(',', '.').to_f : 0
    })

    add_french_date_functions(calculator)
  end

  # pf: Fonctions de date en français. Les champs date sont passés à Dentaku
  # comme objets Date/DateTime natifs (cf. format_value_for_dentaku), ce qui
  # permet d'utiliser aussi directement les opérateurs natifs +/-/</> et la
  # fonction DURATION(n, years|months|days) exposée par Dentaku.
  def add_french_date_functions(calculator)
    calculator.add_function(:AUJOURDHUI, :datetime, -> { Date.current })
    calculator.add_function(:MAINTENANT, :datetime, -> { DateTime.current })

    calculator.add_function(:JOUR, :numeric, -> (d) {
      d.nil? ? nil : to_date(d).day
    })
    calculator.add_function(:MOIS, :numeric, -> (d) {
      d.nil? ? nil : to_date(d).month
    })
    calculator.add_function(:ANNEE, :numeric, -> (d) {
      d.nil? ? nil : to_date(d).year
    })
    # pf: ISO 8601 : lundi = 1 ... dimanche = 7
    calculator.add_function(:JOURSEM, :numeric, -> (d) {
      d.nil? ? nil : to_date(d).cwday
    })

    calculator.add_function(:EST_PASSEE, :logical, -> (d) {
      d.nil? ? false : to_date(d) < Date.current
    })
    calculator.add_function(:EST_FUTURE, :logical, -> (d) {
      d.nil? ? false : to_date(d) > Date.current
    })

    # pf: Calcul d'âge en années révolues, avec gestion du cas où l'anniversaire
    # n'est pas encore passé cette année.
    calculator.add_function(:AGE, :numeric, -> (birth) {
      next nil if birth.nil?
      birth_date = to_date(birth)
      today = Date.current
      age = today.year - birth_date.year
      if today.month < birth_date.month || (today.month == birth_date.month && today.day < birth_date.day)
        age -= 1
      end
      age
    })

    # pf: Alias FR explicites pour DURATION — s'utilisent avec l'arithmétique
    # Date ± Duration. Ex: {DateNaissance} + DUREE_ANNEES(18) → Date 18 ans plus tard.
    calculator.add_function(:DUREE_ANNEES, :duration, -> (n) {
      Dentaku::AST::Duration::Value.new(n.to_i, 'years')
    })
    calculator.add_function(:DUREE_MOIS, :duration, -> (n) {
      Dentaku::AST::Duration::Value.new(n.to_i, 'months')
    })
    calculator.add_function(:DUREE_JOURS, :duration, -> (n) {
      Dentaku::AST::Duration::Value.new(n.to_i, 'days')
    })
  end

  # pf: Les fonctions date acceptent indifféremment Date/DateTime/Time.
  # On normalise vers Date quand l'appelant veut un jour calendrier.
  def to_date(value)
    value.respond_to?(:to_date) ? value.to_date : value
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
        next register_variable(get_champ_numeric_value(champ))
      end

      # New column-based resolution
      column, path = @resolver.resolve_with_path(reference)

      if column.nil?
        raise InvalidFieldReferenceError, reference
      end

      value = extract_column_value(column, path)
      register_variable(format_value_for_dentaku(value, column.type))
    end
  end

  # pf: enregistre une valeur sous un nom de variable unique et retourne
  # ce nom pour injection dans l'expression Dentaku. Dentaku recevra la
  # valeur native (String, Integer, Float) via son hash de variables,
  # sans sérialisation/parsing intermédiaire.
  def register_variable(value)
    @var_counter ||= 0
    @var_counter += 1
    name = "__formula_var_#{@var_counter}__"
    @variables[name] = value
    name
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
      # pf: on passe des booléens natifs à Dentaku (pas 0/1) pour que le
      # typage soit préservé jusqu'à format_result. Une formule `{CaseACocher}`
      # doit rendre "true"/"false" (affiché Oui/Non), pas "1"/"0".
      # Pour l'arithmétique, l'utilisateur doit écrire explicitement
      # `SI({CaseACocher}, 1, 0)` — pas de conversion implicite boolean→number
      # (cohérent avec un langage fonctionnel, Dentaku lève une erreur claire
      # sur `true + 1`).
      # Attention : en Ruby la string "false" est truthy, donc on teste
      # explicitement les valeurs plutôt que de faire `value ? true : false`.
      case value
      when true, Champs::BooleanChamp::TRUE_VALUE then true
      when false, Champs::BooleanChamp::FALSE_VALUE then false
      end
    when :date
      # pf: on passe un objet Date natif à Dentaku plutôt qu'un timestamp.
      # Permet l'usage direct des fonctions natives (DURATION) et custom
      # (AUJOURDHUI, AGE, ANNEE, ...) ainsi que les opérateurs Date ± Date
      # (retourne jours) et Date ± Duration (retourne Date).
      value.present? ? Date.parse(value.to_s) : nil
    when :datetime
      value.present? ? DateTime.parse(value.to_s) : nil
    else
      # pf: text, enum ou inconnu — conservé tel quel (String). Pour faire
      # des maths sur un champ textuel, utiliser explicitement VALEUR({champ}).
      value.to_s
    end
  rescue StandardError
    # pf: pour les dates, on ne peut pas retourner 0 (type incompatible avec
    # l'arithmétique Date). Retourner nil laisse Dentaku propager silencieusement.
    case type
    when :date, :datetime then nil
    else 0
    end
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
      # pf: calcul récursif — la formule référencée peut être numérique, booléenne
      # ou texte. On dispatche selon formule_output_type pour convertir correctement.
      result = compute_value(champ)
      case champ.type_de_champ.formule_output_type
      when 'boolean'
        result == Champs::BooleanChamp::TRUE_VALUE ? 1 : 0
      else # 'number', 'string', ou nil
        result.is_a?(String) && result.match?(/\A-?\d+(\.\d+)?\z/) ? result.to_f : 0
      end
    when 'date'
      # pf: Retourne un objet Date natif (le nom "numeric" est historique ;
      # cette méthode sert de convertisseur type-aware pour Dentaku).
      champ.value.present? ? Date.parse(champ.value) : nil
    when 'datetime'
      champ.value.present? ? DateTime.parse(champ.value) : nil
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
    when Rational
      # pf: Retour de "Date - Date" = jours (Rational exact). On rend
      # l'entier quand c'est entier (Date - Date), le flottant sinon
      # (DateTime - DateTime = jours avec partie fractionnaire).
      result.denominator == 1 ? result.to_i.to_s : result.to_f.to_s
    when Float, BigDecimal
      # Si pas de partie décimale, convertir en entier
      if result % 1 == 0
        result.to_i.to_s
      else
        # Enlever les zéros inutiles à la fin
        result.to_s.sub(/\.?0+$/, '')
      end
    when TrueClass, FalseClass
      # pf: storage aligné avec les champs yes_no/checkbox (Champs::BooleanChamp).
      # Permet une interop propre avec GraphQL/Lexpol et le moteur de conditions.
      # Pour utiliser un booléen en arithmétique (ex: SOMME des vrais), passer
      # explicitement par SI({formule_bool}, 1, 0).
      result ? 'true' : 'false'
    when Date, DateTime, Time
      # pf: Retour de AUJOURDHUI(), MAINTENANT(), ou arithmétique Date ± Duration.
      # Sérialisation ISO 8601 (cohérent avec le stockage natif des champs Date).
      result.iso8601
    else
      result.to_s
    end
  end
end
