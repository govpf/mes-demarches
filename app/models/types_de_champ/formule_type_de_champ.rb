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

  private

  def validate_expression
    return if @type_de_champ.formule_expression.blank?

    expression = @type_de_champ.formule_expression.strip

    if expression.length > 1000
      @type_de_champ.errors.add(:formule_expression, :too_long, count: 1000)
      return
    end

    if expression.scan(/\{[^}]*\}/).any? { |ref| ref.length < 3 }
      @type_de_champ.errors.add(:formule_expression, :invalid_field_reference)
      return
    end

    # pf: détection préalable de '=' seul (confusion fréquente avec '==').
    # Dentaku traite 'x = 5' comme une affectation et remonte un
    # UnboundVariableError peu compréhensible pour l'utilisateur.
    hint = FormulaCalculationService.detect_equals_operator_hint(expression)
    if hint.present?
      @type_de_champ.errors.add(:formule_expression, :invalid_syntax, message: hint)
      return
    end

    # pf: Validation syntaxique Dentaku — on remplace les {tdc123} par des
    # variables fictives pour vérifier la syntaxe sans résoudre les références.
    testable = expression.gsub(/\{[^}]+\}/, 'x')
    calculator = FormulaCalculationService.new_calculator
    ast_node = calculator.ast(testable)

    # pf: Inférence automatique du type de sortie via l'AST Dentaku.
    # Utilisé par le système de conditions pour proposer les bons opérateurs.
    @type_de_champ.formule_output_type = infer_output_type(ast_node)
  rescue Dentaku::ParseError, Dentaku::TokenizerError => e
    @type_de_champ.errors.add(:formule_expression, :invalid_syntax,
                              message: FormulaCalculationService.translate_error(e))
  rescue StandardError
    # Autres erreurs Dentaku (UnboundVariable, etc.) — OK à ce stade,
    # les variables seront résolues au calcul.
  end

  def infer_output_type(ast_node)
    case ast_node&.type
    when :logical then 'boolean'
    when :string then 'string'
    else 'number' # :numeric, nil, ou inconnu → fallback number
    end
  end
end
