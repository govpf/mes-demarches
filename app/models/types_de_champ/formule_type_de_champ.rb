# frozen_string_literal: true

class TypesDeChamp::FormuleTypeDeChamp < TypesDeChamp::TypeDeChampBase
  # pf: enregistré comme validation ActiveModel pour que validate_expression
  # tourne à chaque appel de valid?, pas seulement au chargement initial du
  # TDC. Sans ça, une modif de formule_expression n'était jamais validée
  # côté serveur (le message d'erreur restait vide et la formule invalide
  # pouvait être sauvegardée — cf. double parenthèse )) passée au travers).
  validate :validate_expression

  def estimated_fill_duration(revision)
    0.seconds
  end

  # pf: Une formule est calculée par le système, jamais "remplie" par l'usager.
  # Elle ne doit donc JAMAIS être considérée comme obligatoirement à remplir
  # pour le check au dépôt (cf. Dossier#check_mandatory_and_visible_champs qui
  # appelle mandatory_blank? → champ_blank_or_invalid?). Si la formule plante
  # (source manquante), c'est la SOURCE qui doit bloquer le dépôt, pas la
  # formule — sinon l'usager voit deux messages d'erreur dont un absurde.
  # Defensive : couvre aussi les TDC existants en DB avec mandatory:true issus
  # d'avant le masquage de la case dans l'éditeur.
  def champ_blank_or_invalid?(_champ)
    false
  end

  # pf: Le storage d'une formule reflète son type :
  # - nil → la formule n'a pas pu se calculer (Dentaku silent fail, source
  #   manquante, etc.) → on affiche un marker "—" pour distinguer
  # - "" → la formule a retourné une chaîne vide intentionnellement
  #   (ex: SI(cond, "X", "")) → on affiche vide
  # - boolean → "true"/"false" (cohérence avec yes_no/checkbox)
  # - date → ISO 8601 ("1989-11-15")
  # - datetime → ISO 8601 avec heure ("2026-04-24T15:40:00...")
  # - autres → texte brut
  # À l'affichage usager (vue dossier), on traduit en valeur lisible française.
  FORMULA_NOT_COMPUTED_MARKER = '—'

  def champ_value(champ)
    raw = champ.read_attribute(:value)
    return FORMULA_NOT_COMPUTED_MARKER if raw.nil?
    return champ_default_value if raw == ''

    case @type_de_champ.formule_output_type
    when 'boolean'
      raw == Champs::BooleanChamp::TRUE_VALUE ? 'Oui' : 'Non'
    when 'date'
      format_date_value(raw)
    when 'datetime'
      format_datetime_value(raw)
    else
      super
    end
  end

  def champ_value_for_export(champ, path = :value)
    raw = champ.read_attribute(:value)
    # pf: pour l'export, pas de marker — nil et "" ressortent vides (cellule
    # vide dans CSV/Excel). Le marker "—" est uniquement pour l'affichage UI.
    return nil if raw.blank?

    case @type_de_champ.formule_output_type
    when 'boolean'
      raw == Champs::BooleanChamp::TRUE_VALUE ? 'Oui' : 'Non'
    when 'date'
      format_date_value(raw)
    when 'datetime'
      format_datetime_value(raw)
    else
      super
    end
  end

  # pf: la colonne d'un champ formule doit porter le type réel de sa sortie
  # (number, boolean, string), pas le :text par défaut de TypeDeChamp.column_type.
  # Ça permet à FormulaCalculationService de dispatcher correctement dans
  # format_value_for_dentaku quand une formule est référencée par une autre.
  def columns(procedure:, displayable: true, prefix: nil)
    return [] unless fillable?

    [
      Columns::ChampColumn.new(
        procedure_id: procedure.id,
        stable_id:,
        tdc_type: type_champ,
        label: libelle_with_prefix(prefix),
        type: column_type_from_output,
        displayable:,
        options_for_select:,
        mandatory: mandatory?
      ),
    ]
  end

  private

  def column_type_from_output
    case @type_de_champ.formule_output_type
    when 'boolean' then :boolean
    when 'number' then :decimal
    when 'date' then :date
    when 'datetime' then :datetime
    else :text # 'string' ou nil
    end
  end

  # pf: Parse une chaîne ISO 8601 ("1989-11-15") et la formate en français
  # lisible (date sans heure). Fallback sur la valeur brute en cas d'échec.
  def format_date_value(value)
    parsed = Time.zone.parse(value.to_s)
    parsed ? I18n.l(parsed.to_date, format: '%d %B %Y') : value
  rescue ArgumentError
    value
  end

  # pf: Parse une chaîne ISO 8601 ("2026-04-24T15:40:00") et la formate en
  # français lisible (date + heure, format I18n par défaut). Fallback sur
  # la valeur brute en cas d'échec.
  def format_datetime_value(value)
    parsed = Time.zone.parse(value.to_s)
    parsed ? I18n.l(parsed) : value
  rescue ArgumentError
    value
  end

  def validate_expression
    # pf: Calcul des deps structurées (étape D). has_clock est absent ici car
    # il necessite l'AST Dentaku — il est ajoute plus bas apres construction
    # de l'AST. Les autres cles (champs, has_state, has_identite) sont
    # calculees via regex sur l'expression brute, ce qui est sans risque car
    # les tokens {…} ne peuvent pas apparaitre dans des litteraux Dentaku.
    raw_expression = @type_de_champ.formule_expression
    @type_de_champ.formule_deps = compute_formule_deps_from_expression(raw_expression)

    return if raw_expression.blank?

    expression = raw_expression.strip

    if expression.length > 1000
      @type_de_champ.errors.add(:formule_expression, :too_long, count: 1000)
      return
    end

    if expression.scan(/\{[^}]*\}/).any? { |ref| ref.length < 3 }
      @type_de_champ.errors.add(:formule_expression, :invalid_field_reference)
      return
    end

    # pf: Détection STATIQUE de référence circulaire (au lieu d'au runtime
    # dans FormulaCalculationService#compute_value qui itérait `all_champs`
    # pour chaque calcul, déclenchant des project_champs cascade en draft
    # revision). Le cycle est une propriété intrinsèque du graphe de TDCs
    # de la révision, indépendante du dossier ou des valeurs : on le valide
    # une fois à la sauvegarde et on n'y revient plus.
    if circular_reference?
      @type_de_champ.errors.add(:formule_expression, :circular_reference)
      return
    end

    # pf: Détection STATIQUE de référence "forward" (vers un TDC situé à
    # une position postérieure à la formule courante). L'éditeur frontend
    # filtre déjà les variables proposées via available_columns_for_formula,
    # mais on verrouille côté backend : un déplacement de TDC peut transformer
    # une référence valide en forward reference. Dans ce cas la formule
    # devient invalide et l'admin doit corriger ou changer l'ordre.
    #
    # Backend et frontend partagent exactement la même méthode source
    # (available_columns_for_formula) : pas de divergence possible entre
    # ce que l'éditeur propose et ce que la validation accepte.
    if forward_reference?
      @type_de_champ.errors.add(:formule_expression, :forward_reference)
      return
    end

    # pf: détection préalable de '=' seul (confusion fréquente avec '==').
    # Dentaku traite 'x = 5' comme une affectation et remonte un
    # UnboundVariableError peu compréhensible pour l'utilisateur.
    hint = FormulaCalculationService.detect_equals_operator_hint(expression)
    if hint.present?
      # pf: interpolation via :detail (pas :message, clé réservée par
      # errors.add → non conservée pour la ré-interpolation de full_messages).
      @type_de_champ.errors.add(:formule_expression, :invalid_syntax, detail: hint)
      return
    end

    # pf: Validation syntaxique Dentaku — on remplace les {tdc123} par des
    # variables fictives pour vérifier la syntaxe sans résoudre les références.
    # Chaque référence reçoit un placeholder unique (ref_map placeholder →
    # référence d'origine) pour que l'analyse de l'AST puisse remonter au TDC
    # référencé (cf. détection de condition non booléenne ci-dessous).
    ref_map = {}
    testable = expression.gsub(/\{([^}]+)\}/) do
      placeholder = "__ref_#{ref_map.size + 1}__"
      ref_map[placeholder] = Regexp.last_match(1).strip
      placeholder
    end
    calculator = FormulaCalculationService.new_calculator
    ast_node = calculator.ast(testable)

    # pf: has_clock est calcule via l'AST (pas via regex) pour eviter les
    # faux positifs quand un nom de fonction clock apparait dans un litteraal
    # string. Ex: CONCATENER("AGE(x)", {ref}) → has_clock doit etre absent.
    # L'AST est deja construit ici, on enrichit formule_deps.
    if ast_uses_clock_function?(ast_node)
      deps = @type_de_champ.formule_deps.dup
      deps['has_clock'] = true
      @type_de_champ.formule_deps = deps
    end

    # pf: Garde-fou sémantique — un champ non booléen référencé tel quel comme
    # condition (NON({Liste}), ET({Texte}, ...), SI({Nombre}, ...)) est
    # toujours truthy en sémantique Ruby (seuls false/nil sont falsy) : la
    # condition est constante, c'est une erreur d'admin quasi certaine.
    # Piège typique : un select avec options « Oui »/« Non » à la place d'un
    # champ Oui/Non — NON({Select}) renvoie false quel que soit le choix.
    misuse = find_non_boolean_condition(ast_node, ref_map)
    if misuse
      @type_de_champ.errors.add(:formule_expression, :non_boolean_condition,
                                function: misuse[:function], label: misuse[:label])
      return
    end

    # pf: Inférence automatique du type de sortie.
    # Cas spécial : une expression qui est JUSTE une référence nue `{champ}`
    # a un AST de type Identifier sans info de type — on regarde le type du
    # champ référencé. Sinon, on se base sur l'AST (logical, string, numeric).
    @type_de_champ.formule_output_type = infer_output_type_from_reference(expression) || infer_output_type(ast_node)
  rescue Dentaku::ParseError, Dentaku::TokenizerError => e
    @type_de_champ.errors.add(:formule_expression, :invalid_syntax,
                              detail: FormulaCalculationService.translate_error(e))
  rescue StandardError
    # Autres erreurs Dentaku (UnboundVariable, etc.) — OK à ce stade,
    # les variables seront résolues au calcul.
  end

  # pf: Inférence du type de sortie depuis l'AST Dentaku.
  # SI / IF nativement délègue au type de sa branche `left` (cf. Dentaku::AST::If#type),
  # donc une formule `SI(cond, "OK", "KO")` ressort :string et est correctement
  # mappée à 'string'. Idem pour les autres fonctions (CONCATENER → :string,
  # SOMME → :numeric, etc.) via les alias des classes natives.
  def infer_output_type(ast_node)
    case ast_node&.type
    when :logical then 'boolean'
    when :string then 'string'
    when :datetime then 'datetime'
    when :date then 'date'
    else 'number' # :numeric, nil, ou inconnu → fallback number
    end
  end

  # pf: si l'expression est exactement `{référence}` (une seule référence nue),
  # le type de sortie est celui du champ référencé. Retourne nil si l'expression
  # n'est pas de cette forme (l'AST Dentaku prendra alors le relais).
  def infer_output_type_from_reference(expression)
    return nil unless expression.strip.match?(/\A\{[^}]+\}\z/)

    ref = expression.strip[1..-2].strip
    revision = @type_de_champ.revisions.last
    return nil if revision.nil?

    referenced_tdc = find_referenced_tdc(ref, revision)
    return nil if referenced_tdc.nil?

    case referenced_tdc.type_champ
    when 'checkbox', 'yes_no'
      'boolean'
    when 'integer_number', 'decimal_number'
      'number'
    when 'formule'
      # Transitivité : on hérite du type inféré du champ formule référencé
      referenced_tdc.formule_output_type
    else
      'string'
    end
  end

  def find_referenced_tdc(ref, revision)
    # Supporte les formats {tdc123}, {tdc123/path}, {123} (legacy)
    stable_id = case ref
    when /^tdc(\d+)/ then Regexp.last_match(1).to_i
    when /^\d+$/ then ref.to_i
    end
    return nil if stable_id.nil?
    revision.types_de_champ.find { |t| t.stable_id == stable_id }
  end

  # pf: Détecte si l'expression du TDC en cours de save introduit un cycle
  # dans le graphe des dépendances entre formules. BFS depuis les références
  # directes du TDC courant ; chaque formule référencée est expansée via sa
  # formule_expression stockée. Si on revient sur le stable_id du TDC
  # courant, c'est un cycle.
  #
  # Cas couverts :
  # - Auto-référence : `{Self}` directement dans sa propre formule
  # - Cycle indirect : A → B → A
  # - Cycle long : A → B → C → ... → A
  # Cas non-cycle :
  # - DAG sans retour
  # - Référence à un champ non-formule (terminal de la traversée)
  # - Référence à un champ système (ignoré par extract_dependent_stable_ids)
  def circular_reference?
    current_id = @type_de_champ.stable_id
    return false if current_id.nil?

    revision = @type_de_champ.revisions.last
    return false if revision.nil?

    # pf: snapshot des TDCs de la révision indexés par stable_id, pour
    # éviter un find linéaire à chaque expansion.
    tdcs_by_stable_id = revision.types_de_champ.index_by(&:stable_id)

    visited = Set.new
    queue = extract_dependent_stable_ids(@type_de_champ.formule_expression)

    until queue.empty?
      next_id = queue.shift
      return true if next_id == current_id
      next if visited.include?(next_id)

      visited.add(next_id)
      next_tdc = tdcs_by_stable_id[next_id]
      next unless next_tdc&.formule?

      queue.concat(extract_dependent_stable_ids(next_tdc.formule_expression))
    end

    false
  end

  # pf: Extrait les stable_ids référencés dans une expression au format stocké
  # ({tdc123} ou {tdc123/path}). Les colonnes système ({dossier_number}, etc.)
  # sont ignorées — elles ne sont jamais des formules donc jamais source de cycle.
  def extract_dependent_stable_ids(expression)
    return [] if expression.blank?
    expression.scan(/\{tdc(\d+)/).map { |m| m[0].to_i }
  end

  # pf: Vrai si l'expression référence un stable_id qui n'est pas dans la
  # liste de colonnes autorisées (= TDC situés à une position antérieure ;
  # pour une formule dans un bloc, inclut aussi les siblings antérieurs de
  # la même ligne et les parents hors bloc). Implémenté en réutilisant
  # available_columns_for_formula plutôt qu'en réécrivant la logique de
  # position : garantit que la règle backend est exactement celle de
  # l'autocomplete frontend (même cas répétition, même cas annotation
  # privée référençant des champs publics).
  def forward_reference?
    return false if @type_de_champ.stable_id.nil?

    revision = @type_de_champ.revisions.last
    return false if revision.nil?

    coordinate = revision.coordinate_for(@type_de_champ)
    return false if coordinate.nil?

    allowed_stable_ids = coordinate.available_columns_for_formula
      .filter_map { |col| col.stable_id if col.is_a?(Columns::ChampColumn) }
      .to_set

    # pf: Les TDC repetition n'apparaissent pas dans available_columns_for_formula
    # (repetition.columns retourne les columns des sous-TDC, pas du bloc). Pour
    # les formules-agrégat ({tdc<bloc>}, {tdc<bloc>/sub_<id>}), on autorise les
    # blocs placés AVANT la formule.
    allowed_stable_ids.merge(allowed_repetition_bloc_stable_ids(coordinate))

    extract_dependent_stable_ids(@type_de_champ.formule_expression)
      .any? { |dep_id| !allowed_stable_ids.include?(dep_id) }
  end

  # pf: Renvoie les stable_id des TDC repetition placés avant la formule,
  # éligibles comme cible d'agrégation. Le bloc parent de la formule (si
  # formule dans un bloc) est exclu pour éviter une auto-référence.
  def allowed_repetition_bloc_stable_ids(coordinate)
    revision = coordinate.revision
    formula_position = coordinate.position
    own_parent_position = coordinate.parent&.position
    own_parent_sid = coordinate.parent_type_de_champ&.stable_id

    revision.types_de_champ.filter_map do |tdc|
      next unless tdc.repetition?
      next if tdc.stable_id == own_parent_sid

      bloc_coordinate = revision.coordinate_for(tdc)
      next if bloc_coordinate.nil?

      # Si formule top-level : bloc accepté s'il précède la formule.
      # Si formule dans un bloc : bloc accepté s'il précède le bloc parent.
      reference_position = own_parent_position || formula_position
      next unless bloc_coordinate.position < reference_position

      tdc.stable_id
    end
  end

  # pf: Construit le Hash formule_deps depuis l'expression brute (regex).
  # has_clock est absent ici — il est ajoute separement via l'AST Dentaku
  # dans validate_expression, apres construction de l'AST.
  # Convention : seules les cles vraies sont presentes (sauf 'champs' toujours la).
  # Supporte les deux formats : {tdc123} (format courant) et {123} (ancien format
  # de compatibilite ascendante), ainsi que le chemin optionnel {tdc123/path}.
  FORMULE_DEPS_TDC_PATTERN = /\{tdc(\d+)(?:\/[^}]+)?\}/
  FORMULE_DEPS_LEGACY_PATTERN = /\{(\d+)\}/
  FORMULE_DEPS_STATE_PATTERN = /\{dossier_(depose|en_construction|en_instruction|processed)_at\}/
  FORMULE_DEPS_IDENTITE_PATTERN = /\{(?:individual_|entreprise_)/

  def compute_formule_deps_from_expression(expression)
    deps = {}

    expr_str = expression.to_s
    tdc_ids = expr_str.scan(FORMULE_DEPS_TDC_PATTERN).map { |m| m[0].to_i }
    legacy_ids = expr_str.scan(FORMULE_DEPS_LEGACY_PATTERN).map { |m| m[0].to_i }
    champs = (tdc_ids + legacy_ids).uniq.sort
    deps['champs'] = champs

    deps['has_state'] = true if expr_str.match?(FORMULE_DEPS_STATE_PATTERN)
    deps['has_identite'] = true if expr_str.match?(FORMULE_DEPS_IDENTITE_PATTERN)

    deps
  end

  # pf: Fonctions Dentaku dependantes de "maintenant" (clock-dependent).
  # Detectees via l'AST (pas le regex) pour ne pas matcher les noms de
  # fonction presents dans des litteraux string.
  # Rappel : calculator.add_function(:AGE, ...) → node.class.name == :AGE (Symbol).
  CLOCK_FUNCTION_NAMES = Set[:AUJOURDHUI, :MAINTENANT, :AGE, :EST_PASSEE, :EST_FUTURE].freeze

  # pf: Parcours recursif de l'AST Dentaku pour detecter un appel a une
  # fonction clock. Les noeuds personnalises (add_function) ont
  # node.class.name comme Symbol (ex: :AGE) ; les noeuds built-in ont
  # node.class.name comme String. On s'appuie sur ce discriminant.
  # pf: Dentaku::AST::Negation stocke son operande dans @node (accesseur :node),
  # pas dans :left/:right. On descend explicitement dans :node pour ne pas
  # manquer un appel clock enveloppe par un unaire (ex: -AGE({tdc42})).
  def ast_uses_clock_function?(node)
    return false if node.nil?
    return true if node.class.name.is_a?(Symbol) && CLOCK_FUNCTION_NAMES.include?(node.class.name)

    ast_children(node).any? { |child| ast_uses_clock_function?(child) }
  end

  # pf: Enfants d'un nœud AST Dentaku, toutes formes confondues : fonctions
  # (args), opérateurs binaires (left/right), unaires (node — cf. Negation).
  # Un nœud If expose à la fois args et left/right : le doublon est inoffensif
  # pour une détection (double visite au pire).
  def ast_children(node)
    children = []
    children.concat(node.args) if node.respond_to?(:args) && node.args
    children << node.left if node.respond_to?(:left) && node.left
    children << node.right if node.respond_to?(:right) && node.right
    children << node.node if node.respond_to?(:node) && node.node
    children
  end

  # pf: Fonctions logiques (customs FR + natives Dentaku) dont TOUS les
  # arguments sont des conditions. Clé = node.class.name upcasé, valeur =
  # nom affiché dans le message d'erreur. SI/IF (condition = 1er argument
  # seulement) et les opérateurs infixes &&/||/and/or sont traités à part
  # dans logical_condition_args.
  LOGICAL_FUNCTION_NAMES = {
    NON: 'NON', NOT: 'NOT', ET: 'ET', AND: 'AND', OU: 'OU', OR: 'OR', XOR: 'XOR',
  }.freeze

  # pf: Parcours de l'AST à la recherche d'une référence de champ non booléen
  # utilisée telle quelle en position de condition. Retourne le premier abus
  # trouvé ({ function:, label: }) ou nil. ref_map mappe les placeholders
  # (__ref_N__) vers la référence d'origine ({tdc123}, {dossier_number}, ...).
  def find_non_boolean_condition(node, ref_map)
    return nil if node.nil?

    condition_args, function_label = logical_condition_args(node)
    condition_args&.each do |arg|
      label = non_boolean_reference_label(arg, ref_map)
      return { function: function_label, label: label } if label
    end

    ast_children(node).each do |child|
      found = find_non_boolean_condition(child, ref_map)
      return found if found
    end
    nil
  end

  # pf: Si le nœud attend des conditions booléennes, retourne [args-conditions,
  # nom affichable] ; nil sinon. Trois familles :
  # - fonctions enregistrées (NON, not, ET, and, ...) → node.class.name est un
  #   Symbol (cf. ast_uses_clock_function?), tous les args sont des conditions ;
  # - SI/IF (alias natif Dentaku::AST::If) → seule la condition (1er arg) ;
  # - opérateurs infixes && / || / and / or → left et right.
  def logical_condition_args(node)
    name = node.class.name
    if name.is_a?(Symbol)
      display = LOGICAL_FUNCTION_NAMES[name.to_s.upcase.to_sym]
      return [node.args, display] if display
    elsif node.is_a?(Dentaku::AST::If)
      return [[node.predicate], 'SI']
    elsif node.is_a?(Dentaku::AST::And)
      return [[node.left, node.right], 'ET']
    elsif node.is_a?(Dentaku::AST::Or)
      return [[node.left, node.right], 'OU']
    end
    nil
  end

  # pf: Libellé du TDC référencé si `arg` est une référence nue vers un champ
  # non booléen ; nil dans tous les cas légitimes. Prudence par défaut :
  # - sous-propriété ({tdc123/path}) : type non trivial → laissé passer ;
  # - colonne système ({dossier_number}, ...) : pas un TDC → laissé passer ;
  # - date/datetime : passés nil quand vides (falsy) → NON({Date}) teste
  #   « non renseignée », usage légitime.
  def non_boolean_reference_label(arg, ref_map)
    return nil unless arg.is_a?(Dentaku::AST::Identifier)

    ref = ref_map[arg.identifier.to_s]
    return nil if ref.nil? || ref.include?('/')

    revision = @type_de_champ.revisions.last
    return nil if revision.nil?

    tdc = find_referenced_tdc(ref, revision)
    return nil if tdc.nil? || boolean_condition_compatible_tdc?(tdc)

    tdc.libelle
  end

  def boolean_condition_compatible_tdc?(tdc)
    case tdc.type_champ
    when 'checkbox', 'yes_no', 'date', 'datetime'
      true
    when 'formule'
      tdc.formule_output_type == 'boolean'
    else
      false
    end
  end
end
