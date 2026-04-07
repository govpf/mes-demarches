# frozen_string_literal: true

class TypesDeChamp::FormuleTypeDeChamp < TypesDeChamp::TypeDeChampBase
  def initialize(type_de_champ)
    super
    validate_expression
  end

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

    # pf: Validation syntaxique Dentaku — on remplace les {tdc123} par des
    # variables fictives pour vérifier la syntaxe sans résoudre les références.
    testable = expression.gsub(/\{[^}]+\}/, 'x')
    calculator = FormulaCalculationService.new_calculator
    calculator.ast(testable)
  rescue Dentaku::ParseError => e
    @type_de_champ.errors.add(:formule_expression, :invalid_syntax, message: e.message)
  rescue Dentaku::TokenizerError => e
    @type_de_champ.errors.add(:formule_expression, :invalid_syntax, message: e.message)
  rescue StandardError
    # Autres erreurs Dentaku (UnboundVariable, etc.) — OK à ce stade,
    # les variables seront résolues au calcul.
  end
end
