
# frozen_string_literal: true

class FormulaCalculationService
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
    # pf: cache value→nom de variable pour dédoublonner les références multiples
    # à la même source dans une expression. Sans ce cache, register_variable
    # ajoutait une nouvelle entrée à chaque appel — ex: SUBSTITUE({tdc683},...)
    # apparaissant 4 fois créait 4 variables identiques dans @variables.
    @value_to_var = {}

    # pf: La détection de référence circulaire est faite STATIQUEMENT à la
    # validation du TDC formule (cf. FormuleTypeDeChamp#validate_expression
    # → circular_reference?). Un cycle est une propriété intrinsèque du
    # graphe de TDCs de la révision, pas du dossier ou des valeurs : pas
    # besoin de la re-vérifier à chaque compute. Avant ce déplacement, le
    # check runtime déclenchait `all_champs` (= project_champs cascade qui
    # recompute toutes les formules en draft revision) à chaque calcul.

    # Resolve field references using columns
    resolved_expression = resolve_column_references(expression)

    # Calculate with Dentaku
    result = @calculator.evaluate(resolved_expression, @variables)

    # pf: Dentaku.evaluate retourne nil silencieusement quand l'évaluation
    # échoue (type mismatch, fonction inconnue, source manquante, etc.).
    # On propage ce nil jusqu'à la couche de stockage pour le distinguer
    # d'une string vide légitime (ex: SI(cond, "X", "")). À l'affichage,
    # nil → marker "—", "" → vide. Permet aussi de retirer la validation
    # presence qui bloquait inutilement le dépôt.
    return nil if result.nil?

    # Format result
    format_result(result)
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
  # Le paramètre locale: est conservé pour rétro-compatibilité d'API mais
  # n'a plus d'effet sur l'enregistrement des fonctions — les noms (SI,
  # ARRONDI, SOMME…) sont des identifiants d'API stables stockés en DB,
  # indépendants de la locale d'affichage de l'utilisateur.
  def self.new_calculator(locale: I18n.locale)
    _ = locale
    calculator = Dentaku::Calculator.new
    new_instance = allocate
    new_instance.send(:add_french_functions, calculator)
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

  # pf: Mapping inverse des classes natives Dentaku vers les noms FR aliasés
  # (cf. config/initializers/dentaku_french_aliases.rb). Permet aux messages
  # d'erreur de référencer le nom que l'admin a tapé (`SI`, `SOMME`, ...) au
  # lieu de la classe interne (If, Sum, ...).
  NATIVE_TO_FR_NAMES = {
    'If' => 'SI',
    'Sum' => 'SOMME',
    'Avg' => 'MOYENNE',
    'Round' => 'ARRONDI',
    'Concat' => 'CONCATENER',
    'StringFunctions::Concat' => 'CONCATENER',
    'Left' => 'GAUCHE',
    'StringFunctions::Left' => 'GAUCHE',
    'Right' => 'DROITE',
    'StringFunctions::Right' => 'DROITE',
    'Mid' => 'STXT',
    'StringFunctions::Mid' => 'STXT',
    'Len' => 'NBCAR',
    'StringFunctions::Len' => 'NBCAR',
  }.freeze

  def self.format_operator(klass)
    # Fonction custom (CHERCHE, SUBSTITUE, MAJUSCULE, AGE, ...) : klass.name
    # est un Symbol — ex: :SI → "SI"
    return klass.name.to_s.upcase if klass.name.is_a?(Symbol)

    name = klass.name.to_s
    # Opérateur built-in (Dentaku::AST::Addition → "+") ou fonction native
    # aliasée (Dentaku::AST::If → "SI")
    short = name.sub('Dentaku::AST::', '')
    NATIVE_TO_FR_NAMES[short] || OPERATOR_SYMBOLS[short] || short
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

  private

  def create_calculator
    # pf: Les fonctions FR (SI, ARRONDI, SOMME, AGE, ...) sont enregistrées
    # systématiquement, indépendamment de @locale. Les noms de fonctions sont
    # des identifiants stables stockés en DB ; l'admin a écrit "SI(...)" et
    # ce nom doit être résolu au calcul peu importe la langue d'affichage de
    # l'utilisateur qui consulte le dossier. Sans ça, un instructeur en UI
    # anglaise voyait toutes les formules retourner nil silencieusement.
    calculator = Dentaku::Calculator.new
    add_french_functions(calculator)
    calculator
  end

  def add_french_functions(calculator)
    # pf: La majorité des fonctions FR sont des **alias purs des classes
    # natives Dentaku** déclarés dans config/initializers/dentaku_french_aliases.rb.
    # L'avantage : l'inférence de type de l'AST suit la classe native (ex: SI
    # infère le type de ses branches dynamiquement), ce qui évite le bug de
    # "0.0" affiché pour une formule SI retournant du texte. Aliases couverts :
    # SI, SOMME, MOYENNE, ABS, ARRONDI, CONCATENER, GAUCHE, DROITE, STXT,
    # NBCAR, CHERCHE, SUBSTITUE. Ne pas les redéclarer ici : ça écraserait
    # l'alias par un add_function avec un type figé.
    #
    # MIN et MAX sont natifs Dentaku sous le même nom — pas besoin d'alias.
    #
    # Restent custom ici uniquement les fonctions qui n'ont pas d'équivalent
    # natif (MAJUSCULE, MINUSCULE, SUPPRESPACE, VALEUR), les opérateurs
    # logiques avec sémantique Ruby pure (ET, OU, NON) car les natifs
    # AND/OR/NOT sont strictement booléens (retournent nil sur 0/""), et les
    # fonctions de date.

    # pf: Sémantique Ruby pure — seuls false/nil sont falsy. L'admin écrit
    # ses comparaisons explicitement (`ET({Age} > 18, {Habitant} == "Yes")`).
    calculator.add_function(:ET, :logical, -> (*args) {
      raise Dentaku::ArgumentError, 'ET() nécessite au moins un argument' if args.empty?
      args.all? { |arg| arg }
    })
    calculator.add_function(:OU, :logical, -> (*args) {
      raise Dentaku::ArgumentError, 'OU() nécessite au moins un argument' if args.empty?
      args.any? { |arg| arg }
    })
    calculator.add_function(:NON, :logical, -> (value) { !value })

    calculator.add_function(:MAJUSCULE, :string, -> (text) { text.to_s.upcase })
    calculator.add_function(:MINUSCULE, :string, -> (text) { text.to_s.downcase })
    calculator.add_function(:SUPPRESPACE, :string, -> (text) { text.to_s.strip.gsub(/\s+/, ' ') })

    # pf: CHERCHE custom (case-insensitive, 3e arg start, retourne 0 si non
    # trouvé) — sémantique Excel utile pour l'admin, divergente de FIND natif.
    calculator.add_function(:CHERCHE, :numeric, -> (search, text, start = 1) {
      pos = text.to_s.downcase.index(search.to_s.downcase, start.to_i - 1)
      pos ? pos + 1 : 0
    })

    # pf: SUBSTITUE custom (gsub — remplace toutes les occurrences). Substitute
    # natif Dentaku fait sub (première occurrence seulement).
    calculator.add_function(:SUBSTITUE, :string, -> (text, old_str, new_str) {
      text.to_s.gsub(old_str.to_s, new_str.to_s)
    })

    # pf: conversion explicite texte → nombre (équivalent VALUE/CNUM d'Excel).
    # Gère le séparateur décimal français (virgule) et retourne 0 si non parsable.
    calculator.add_function(:VALEUR, :numeric, -> (text) {
      str = text.to_s.strip
      return 0 if str.empty?
      match = str.match(/-?\d+(?:[.,]\d+)?/)
      match ? match[0].tr(',', '.').to_f : 0
    })

    # pf: ENTIER tronque vers zéro (to_i Ruby) — différent de ARRONDI_INF (floor).
    # ENTIER(-3.7) = -3 alors que ARRONDI_INF(-3.7) = -4.
    # Utile pour caster un résultat numérique en entier afin d'éviter "xxx.0"
    # en concaténation : CONCATENER("00", ENTIER({tdc750}), "000").
    calculator.add_function(:ENTIER, :numeric, -> (n) {
      next nil if n.nil?
      n.to_f.to_i
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
    # pf: DUREE_SEMAINES(n) = n * 7 jours — pas de unit 'weeks' dans Dentaku,
    # on retombe sur 'days'.
    calculator.add_function(:DUREE_SEMAINES, :duration, -> (n) {
      Dentaku::AST::Duration::Value.new(n.to_i * 7, 'days')
    })

    # pf: Intervalles entre deux dates. Toutes nil-safe (n'importe quel
    # argument nil → retourne nil pour propager le manque de donnée).
    calculator.add_function(:JOURS_ENTRE, :numeric, -> (d1, d2) {
      next nil if d1.nil? || d2.nil?
      (to_date(d2) - to_date(d1)).to_i
    })
    # pf: Troncature vers zéro (5 jours → 0 semaine, -5 jours → 0 semaine).
    # Pas la division entière Ruby (qui fait floor vers -∞).
    calculator.add_function(:SEMAINES_ENTRE, :numeric, -> (d1, d2) {
      next nil if d1.nil? || d2.nil?
      days = (to_date(d2) - to_date(d1)).to_i
      days.abs.div(7) * (days.negative? ? -1 : 1)
    })
    # pf: Différence en mois calendaires, indépendante du jour du mois
    # (31 jan → 28 fév = 1, comme attendu par les usagers).
    calculator.add_function(:MOIS_ENTRE, :numeric, -> (d1, d2) {
      next nil if d1.nil? || d2.nil?
      a = to_date(d1)
      b = to_date(d2)
      (b.year - a.year) * 12 + (b.month - a.month)
    })
    # pf: Années révolues (même logique que AGE, généralisée à deux dates).
    # Symétrique : ANNEES_ENTRE(a, b) == -ANNEES_ENTRE(b, a).
    # On calcule toujours sur (min, max) puis on rétablit le signe.
    calculator.add_function(:ANNEES_ENTRE, :numeric, -> (d1, d2) {
      next nil if d1.nil? || d2.nil?
      a = to_date(d1)
      b = to_date(d2)
      sign = b >= a ? 1 : -1
      from, to = sign == 1 ? [a, b] : [b, a]
      years = to.year - from.year
      if to.month < from.month || (to.month == from.month && to.day < from.day)
        years -= 1
      end
      years * sign
    })
  end

  # pf: Les fonctions date acceptent indifféremment Date/DateTime/Time.
  # On normalise vers Date quand l'appelant veut un jour calendrier.
  def to_date(value)
    value.respond_to?(:to_date) ? value.to_date : value
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

      # pf: Blocs répétables — agrégation hors bloc (chantier formule-agrégat).
      # Dentaku 3.5.4 supporte SUM/COUNT/MAX/MIN/AVG sur arrays bindings.
      # Le binding {bloc} reçoit la liste des row_ids (suffit pour COUNT) ;
      # {bloc/sub} reçoit un array de scalaires type-aware.
      case column
      when FormulaColumnResolver::RepetitionRef
        next register_variable(extract_repetition_row_ids(column.bloc_tdc))
      when FormulaColumnResolver::RepetitionSubChampRef
        next register_variable(extract_repetition_values(column.bloc_tdc, column.sub_tdc))
      end

      if column.nil?
        raise InvalidFieldReferenceError, reference
      end

      value = extract_column_value(column, path)
      register_variable(format_value_for_dentaku(value, column.type))
    end
  end

  # pf: Renvoie l'array des row_ids du bloc — utilisé pour COUNT/NB({bloc}).
  # On lit les RepetitionChamps (un par row, créé dès repetition_add_row),
  # plus fiable que de passer par les sous-champs (qui n'existent que si
  # l'usager les a saisis — un row vide n'aurait sinon aucun champ).
  def extract_repetition_row_ids(bloc_tdc)
    all_champs
      .select { |c| c.stable_id == bloc_tdc.stable_id && c.row_id.present? }
      .map(&:row_id)
      .uniq
  end

  # pf: Renvoie l'array des valeurs (type-aware) d'un sous-champ de toutes
  # les lignes du bloc. Les valeurs nil sont filtrées pour éviter qu'une
  # ligne incomplète n'écrase une agrégation (SUM, MAX) — comportement
  # cohérent avec les agrégateurs SQL et avec format_result qui rend nil
  # quand le calcul échoue (ex: MAX sur array vide).
  def extract_repetition_values(_bloc_tdc, sub_tdc)
    rows_champs = all_champs
      .select { |c| c.row_id.present? && c.stable_id == sub_tdc.stable_id }
      .sort_by(&:row_id)

    rows_champs.filter_map { |champ| coerce_repetition_champ_value(champ, sub_tdc) }
  end

  # pf: Conversion typée d'un champ sous-TDC vers le type Ruby attendu par
  # Dentaku. Distincte de format_value_for_dentaku (qui prend un type Column,
  # pas type_champ). Retourne nil pour les champs vides afin d'être filtrés
  # par filter_map dans extract_repetition_values.
  def coerce_repetition_champ_value(champ, tdc)
    return nil if champ.value.blank?

    case tdc.type_champ
    when 'integer_number'
      champ.value.to_i
    when 'decimal_number', 'number'
      champ.value.to_f
    when 'date'
      Date.parse(champ.value) rescue nil # rubocop:disable Style/RescueModifier
    when 'datetime'
      DateTime.parse(champ.value) rescue nil # rubocop:disable Style/RescueModifier
    when 'yes_no'
      champ.value == 'true'
    when 'checkbox'
      champ.value == 'on'
    else
      champ.value.to_s
    end
  end

  # pf: enregistre une valeur sous un nom de variable unique et retourne
  # ce nom pour injection dans l'expression Dentaku. Dentaku recevra la
  # valeur native (String, Integer, Float) via son hash de variables,
  # sans sérialisation/parsing intermédiaire.
  #
  # Dédoublonnage : si la même valeur est référencée plusieurs fois dans
  # l'expression (ex: {tdc683} apparaît 4 fois), on réutilise le nom de
  # variable déjà enregistré au lieu d'en créer un nouveau. Bénéfice :
  # @variables reste compact, et Dentaku peut potentiellement memoizer les
  # sous-AST identiques sur la même variable.
  def register_variable(value)
    @value_to_var ||= {}
    return @value_to_var[value] if @value_to_var.key?(value)

    @var_counter ||= 0
    @var_counter += 1
    name = "__formula_var_#{@var_counter}__"
    @variables[name] = value
    @value_to_var[value] = name
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
      # pf: une formule de type 'number' qui retourne un entier (ex: ARRONDI(x, 0)
      # → Integer 3 → stocké "3") doit rester Integer quand elle est référencée
      # par une autre formule, sinon CONCATENER("00", {tdc_A}, "000") ressort
      # "003.0000" parce qu'un Float 3.0 est injecté dans Dentaku.
      # La value reçue peut être String ("3.7"), Float (4.0 après cast colonne)
      # ou Integer — on normalise vers Integer quand la valeur est sans partie
      # décimale, Float sinon.
      return 0 if value.blank?
      case value
      when Integer then value
      when Float, BigDecimal then value % 1 == 0 ? value.to_i : value.to_f
      else
        s = value.to_s
        Integer(s, exception: false) || s.to_f
      end
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
    # pf: Lookup direct sur la collection au lieu de matérialiser via project_champs.
    # project_champs_*_all itère tous les TDC de la révision et appelle project_champ
    # pour chacun, ce qui :
    #   - construit en mémoire un Champ vide pour chaque TDC sans champ persisté
    #     (utile à l'affichage admin, inutile au calcul de formule),
    #   - en draft revision, recalcule chaque champ formule via project_champ
    #     (cascade O(N TDC) déclenchée pour calculer UNE formule).
    #
    # Sémantique buffer+main : quand le dossier est sur user:buffer, un Champ
    # source non modifié par l'usager n'a PAS de version buffer (il vit
    # uniquement sur main). Pour pouvoir résoudre les références dans une
    # formule, on doit voir buffer ET main, avec le buffer prioritaire pour le
    # même public_id. C'est la sémantique de DossierChampsConcern#champs_on_stream
    # qu'on reproduit ici pour la LECTURE (le service est utilisé pour calculer,
    # pas pour décider du stream de persistence — c'est compute_formulas_in_order
    # qui s'en charge avec un filtre strict par stream).
    #
    # Pour les formules amont (transitivité), la valeur est lue via @value_overrides
    # par compute_formulas_in_order avant même d'arriver dans all_champs.
    @all_champs ||= if @dossier.stream == Champ::USER_BUFFER_STREAM
      buffer_champs = @dossier.champs.filter { |c| c.stream == Champ::USER_BUFFER_STREAM }
      main_champs = @dossier.champs.filter { |c| c.stream == Champ::MAIN_STREAM }
      (buffer_champs + main_champs).uniq(&:public_id)
    else
      @dossier.champs.filter { |c| c.stream == @dossier.stream }
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
