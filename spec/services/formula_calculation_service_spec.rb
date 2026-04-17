# frozen_string_literal: true

describe FormulaCalculationService do
  let(:dossier) { create(:dossier) }
  let(:service) { described_class.new(dossier) }
  let(:procedure) { create(:procedure, :published) }
  let(:dossier_with_revision) { create(:dossier, procedure: procedure) }

  describe '#compute_value' do
    context 'with simple arithmetic expressions' do
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      before do
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '2 + 3'))
      end

      it 'computes basic arithmetic' do
        expect(service.compute_value(formule_champ)).to eq('5')
      end
    end

    context 'with field references' do
      let(:procedure) {
        create(:procedure, :published, types_de_champ_public: [
          { type: :integer_number, libelle: 'Montant HT' },
          { type: :decimal_number, libelle: 'Taux TVA' },
          { type: :formule, libelle: 'Total TTC' }
        ])
      }
      let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }
      let(:montant_champ) { dossier.project_champs_public[0] }
      let(:taux_champ) { dossier.project_champs_public[1] }
      let(:formule_champ) { dossier.project_champs_public[2] }
      let(:service) { described_class.new(dossier, locale: :fr) }

      before do
        montant_champ.update(value: '1000')
        taux_champ.update(value: '0.2')

        expr, _deps = FormulaExpressionService.convert_to_stable_ids(
          '{Montant HT} * (1 + {Taux TVA})',
          procedure.active_revision
        )
        formule_champ.type_de_champ.update(formule_expression: expr)
      end

      it 'resolves field references and computes' do
        expect(service.compute_value(formule_champ)).to eq('1200')
      end
    end

    context 'SOMME, MOYENNE, MIN, MAX functions' do
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      it 'SOMME works with variadic arguments' do
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: 'SOMME(1, 2, 3)'))
        expect(service.compute_value(formule_champ)).to eq('6')
      end

      it 'MOYENNE works with variadic arguments' do
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: 'MOYENNE(10, 20, 30)'))
        expect(service.compute_value(formule_champ)).to eq('20')
      end

      it 'MIN works with variadic arguments' do
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: 'MIN(5, 2, 8)'))
        expect(service.compute_value(formule_champ)).to eq('2')
      end

      it 'MAX works with variadic arguments' do
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: 'MAX(5, 2, 8)'))
        expect(service.compute_value(formule_champ)).to eq('8')
      end

      # Note: Array arguments are tested indirectly via args.flatten in function definitions
      # When PLUCK() returns an array (future feature with repetable blocks), functions will handle it correctly
      # Example: SOMME(PLUCK(repetable_block, 'quantity')) will work because PLUCK returns [10, 20, 30]
      # and SOMME receives it as a single array argument, which flatten() handles
    end

    context 'ET/OU/NON functions with real procedure and revision' do
      let(:procedure) {
        create(:procedure, :published, types_de_champ_public: [
          { type: :integer_number, libelle: 'Prix 1' },
          { type: :integer_number, libelle: 'Prix 2' },
          { type: :integer_number, libelle: 'Prix 3' },
          { type: :formule, libelle: 'Résultat' }
        ])
      }
      let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }
      let(:prix1) { dossier.project_champs_public[0] }
      let(:prix2) { dossier.project_champs_public[1] }
      let(:prix3) { dossier.project_champs_public[2] }
      let(:formule) { dossier.project_champs_public[3] }

      before do
        prix1.update(value: '100')
        prix2.update(value: '200')
        prix3.update(value: '250')
      end

      it 'ET returns true when all conditions are true' do
          expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(ET({Prix 1} > 50, {Prix 2} > 100), "OK", "KO")', procedure.active_revision)
          formule.type_de_champ.update(formule_expression: expr)

          service = described_class.new(dossier, locale: :fr)
          expect(service.compute_value(formule)).to eq('OK')
        end

      it 'ET returns false when one condition is false' do
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(ET({Prix 1} > 50, {Prix 2} > 300), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('KO')
      end

      it 'ET works with 3+ conditions' do
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(ET({Prix 1} > 50, {Prix 2} > 100, {Prix 3} < 300), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('OK')
      end

      it 'OU returns true when at least one condition is true' do
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(OU({Prix 1} < 50, {Prix 2} > 100), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('OK')
      end

      it 'OU returns false when all conditions are false' do
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(OU({Prix 1} < 50, {Prix 2} < 100), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('KO')
      end

      it 'OU works with 3+ conditions' do
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(OU({Prix 1} < 50, {Prix 2} < 100, {Prix 3} > 200), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('OK')
      end

      it 'NON inverts a true condition' do
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(NON({Prix 1} > 50), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('KO')
      end

      it 'NON inverts a false condition' do
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(NON({Prix 1} < 50), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('OK')
      end

      it 'ET and OU can be nested' do
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(OU(ET({Prix 1} > 50, {Prix 2} > 100), {Prix 3} < 100), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('OK')
      end

      it 'ET treats zero as false' do
        prix1 = dossier.project_champs_public.first
        prix1.update(value: '0')
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(ET({Prix 1}, {Prix 2} > 100), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('KO')
      end

      it 'OU treats zero as false but passes with other true' do
        prix1 = dossier.project_champs_public.first
        prix1.update(value: '0')
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(OU({Prix 1}, {Prix 2} > 100), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('OK')
      end
    end

    context 'with syntax errors' do
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      before do
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '2 + + 3'))
      end

      it 'handles syntax errors gracefully' do
        result = service.compute_value(formule_champ)
        expect(result).to include('Erreur').or include('erreur').or be_empty
      end
    end

    context 'with French text functions' do
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      def compute(expression)
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: expression))
        service.compute_value(formule_champ)
      end

      it 'CONCATENER joins strings' do
        expect(compute("CONCATENER('Bon', 'jour')")).to eq('Bonjour')
      end

      it 'GAUCHE extracts left characters' do
        expect(compute("GAUCHE('Bonjour', 3)")).to eq('Bon')
      end

      it 'DROITE extracts right characters' do
        expect(compute("DROITE('Bonjour', 4)")).to eq('jour')
      end

      it 'STXT extracts substring (1-based)' do
        expect(compute("STXT('Bonjour', 4, 4)")).to eq('jour')
      end

      it 'NBCAR returns string length' do
        expect(compute("NBCAR('Bonjour')")).to eq('7')
      end

      it 'CHERCHE finds substring position (case insensitive, 1-based)' do
        expect(compute("CHERCHE('jour', 'Bonjour')")).to eq('4')
      end

      it 'CHERCHE returns 0 when not found' do
        expect(compute("CHERCHE('xyz', 'Bonjour')")).to eq('0')
      end

      it 'SUBSTITUE replaces text' do
        expect(compute("SUBSTITUE('Bonjour monde', 'monde', 'terre')")).to eq('Bonjour terre')
      end

      it 'MAJUSCULE converts to uppercase' do
        expect(compute("MAJUSCULE('bonjour')")).to eq('BONJOUR')
      end

      it 'MINUSCULE converts to lowercase' do
        expect(compute("MINUSCULE('BONJOUR')")).to eq('bonjour')
      end

      it 'SUPPRESPACE trims and collapses spaces' do
        expect(compute("SUPPRESPACE('  bon   jour  ')")).to eq('bon jour')
      end
    end

    # pf: régression — un champ texte référencé nu doit retourner son contenu,
    # et non être silencieusement converti en 0 via extract_number_from_text.
    context 'with text field references (non-regression for silent ->0 coercion)' do
      let(:procedure) {
        create(:procedure, :published, types_de_champ_public: [
          { type: :text, libelle: 'Text court' },
          { type: :text, libelle: 'Prénom' },
          { type: :text, libelle: 'Nom' },
          { type: :text, libelle: 'SIRET' },
          { type: :text, libelle: 'Prix texte' },
          { type: :formule, libelle: 'Résultat' }
        ])
      }
      let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }
      let(:text_court) { dossier.project_champs_public[0] }
      let(:prenom)     { dossier.project_champs_public[1] }
      let(:nom)        { dossier.project_champs_public[2] }
      let(:siret)      { dossier.project_champs_public[3] }
      let(:prix_texte) { dossier.project_champs_public[4] }
      let(:formule)    { dossier.project_champs_public[5] }
      let(:service)    { described_class.new(dossier, locale: :fr) }

      def compute_with(expression)
        expr, _deps = FormulaExpressionService.convert_to_stable_ids(expression, procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        service.compute_value(formule)
      end

      it 'returns the raw text of a referenced text field' do
        text_court.update(value: 'Bonjour')
        expect(compute_with('{Text court}')).to eq('Bonjour')
      end

      it 'CONCATENER works with text field references' do
        prenom.update(value: 'Jean')
        nom.update(value: 'Dupont')
        expect(compute_with('CONCATENER({Prénom}, " ", {Nom})')).to eq('Jean Dupont')
      end

      it 'STXT preserves leading zeros when extracting from a text field' do
        siret.update(value: '01234567890123')
        expect(compute_with('STXT({SIRET}, 1, 3)')).to eq('012')
      end

      it 'STXT preserves a middle zero' do
        siret.update(value: '12305678')
        expect(compute_with('STXT({SIRET}, 3, 2)')).to eq('30')
      end

      it 'VALEUR converts a text field to a number for arithmetic' do
        prix_texte.update(value: '42,5')
        expect(compute_with('VALEUR({Prix texte}) * 2')).to eq('85')
      end

      it 'VALEUR returns 0 for non-numeric text' do
        prix_texte.update(value: 'abc')
        expect(compute_with('VALEUR({Prix texte})')).to eq('0')
      end

      it 'escapes double quotes in text values' do
        text_court.update(value: 'Dit "bonjour"')
        expect(compute_with('{Text court}')).to eq('Dit "bonjour"')
      end

      it 'escapes backslashes in text values' do
        text_court.update(value: 'a\\b')
        expect(compute_with('{Text court}')).to eq('a\\b')
      end

      it 'returns empty string for an empty text field' do
        text_court.update(value: '')
        expect(compute_with('{Text court}')).to eq('')
      end
    end

    # pf: Les formules booléennes stockent "true"/"false" pour être cohérentes
    # avec les champs yes_no/checkbox (Champs::BooleanChamp). Permet interop
    # propre avec GraphQL/Lexpol et moteur de conditions.
    context 'with boolean expressions' do
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      it 'returns "true" for a true comparison' do
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '5 > 3'))
        expect(service.compute_value(formule_champ)).to eq('true')
      end

      it 'returns "false" for a false comparison' do
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '5 < 3'))
        expect(service.compute_value(formule_champ)).to eq('false')
      end

      it 'returns "true" for ET with all truthy' do
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: 'ET(5 > 3, 10 > 1)'))
        expect(service.compute_value(formule_champ)).to eq('true')
      end
    end

    # pf: quand une formule référence une autre formule booléenne,
    # format_value_for_dentaku doit convertir "true"/"false" correctement
    # (bug latent si on fait seulement `value ? 1 : 0` car "false" est truthy).
    context 'when a formula references another boolean formula' do
      let(:procedure) {
        create(:procedure, :published, types_de_champ_public: [
          { type: :integer_number, libelle: 'Age' },
          { type: :formule, libelle: 'Majeur' }, # sera défini comme {Age} >= 18
          { type: :formule, libelle: 'Label' }   # sera défini comme SI({Majeur}, "adulte", "mineur")
        ])
      }
      let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }
      let(:age_champ) { dossier.project_champs_public[0] }
      let(:majeur_champ) { dossier.project_champs_public[1] }
      let(:label_champ) { dossier.project_champs_public[2] }
      let(:service) { described_class.new(dossier, locale: :fr) }

      before do
        expr_majeur, _ = FormulaExpressionService.convert_to_stable_ids('{Age} >= 18', procedure.active_revision)
        majeur_champ.type_de_champ.update(formule_expression: expr_majeur)
        majeur_champ.type_de_champ.valid? # trigger output_type inference
        majeur_champ.type_de_champ.save!

        expr_label, _ = FormulaExpressionService.convert_to_stable_ids('SI({Majeur}, "adulte", "mineur")', procedure.active_revision)
        label_champ.type_de_champ.update(formule_expression: expr_label)
      end

      it 'handles true case correctly' do
        age_champ.update(value: '25')
        majeur_champ.update(value: service.compute_value(majeur_champ)) # "true"
        expect(service.compute_value(label_champ)).to eq('adulte')
      end

      it 'handles false case correctly (no "false" truthy bug)' do
        age_champ.update(value: '15')
        majeur_champ.update(value: service.compute_value(majeur_champ)) # "false"
        expect(service.compute_value(label_champ)).to eq('mineur')
      end
    end

    # pf: pattern recommandé pour convertir explicitement des booléens en
    # nombres — SI(..., 1, 0). Pas de conversion implicite boolean→number.
    context 'counting booleans explicitly via SI' do
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      it 'SOMME(SI(cond1,1,0), SI(cond2,1,0)) counts truthy conditions' do
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: 'SOMME(SI(5 > 3, 1, 0), SI(2 > 10, 1, 0), SI(1 == 1, 1, 0))'))
        expect(service.compute_value(formule_champ)).to eq('2')
      end
    end
  end

  # pf: traductions françaises des erreurs Dentaku
  describe '.translate_error' do
    it 'translates undefined function in French' do
      error = begin
        FormulaCalculationService.new_calculator.evaluate!('FOO(1)')
              rescue Dentaku::ParseError => e
                e
      end
      expect(described_class.translate_error(error)).to eq("La fonction 'foo' n'existe pas")
    end

    it 'translates unbalanced parenthesis in French' do
      error = begin
        FormulaCalculationService.new_calculator.evaluate!('(1+2')
              rescue Dentaku::TokenizerError => e
                e
      end
      expect(described_class.translate_error(error)).to eq("Trop de parenthèses ouvrantes '('")
    end

    it 'translates too few operands in French with readable operator symbol' do
      error = begin
        FormulaCalculationService.new_calculator.evaluate!('1 +')
              rescue Dentaku::ParseError => e
                e
      end
      msg = described_class.translate_error(error)
      expect(msg).to include("manque d'arguments")
      expect(msg).to include("'+'")
      expect(msg).not_to include('Dentaku::AST')
      expect(msg).not_to include('#<Class')
    end

    it 'translates too few operands for a custom function (SI) with readable name' do
      calc = FormulaCalculationService.new_calculator(locale: :fr)
      error = begin
        calc.evaluate!('SI(1)')
              rescue Dentaku::ParseError => e
                e
      end
      msg = described_class.translate_error(error)
      expect(msg).to include("'SI'")
      expect(msg).not_to include('#<Class')
    end

    it 'formats arithmetic operators as their symbol' do
      expect(described_class.format_operator(Dentaku::AST::Addition)).to eq('+')
      expect(described_class.format_operator(Dentaku::AST::Multiplication)).to eq('*')
      expect(described_class.format_operator(Dentaku::AST::Division)).to eq('/')
      expect(described_class.format_operator(Dentaku::AST::Equal)).to eq('==')
    end

    it 'translates unbound variable in French' do
      error = begin
        FormulaCalculationService.new_calculator.evaluate!('x + 1')
              rescue Dentaku::UnboundVariableError => e
                e
      end
      expect(described_class.translate_error(error)).to eq("La variable 'x' n'est pas définie")
    end
  end

  describe '.detect_equals_operator_hint' do
    it 'detects single = and returns hint' do
      expect(described_class.detect_equals_operator_hint('SI({x} = 5, 1, 0)')).to include("Utilisez '=='")
    end

    it 'does not trigger on ==' do
      expect(described_class.detect_equals_operator_hint('SI({x} == 5, 1, 0)')).to be_nil
    end

    it 'does not trigger on >=' do
      expect(described_class.detect_equals_operator_hint('SI({x} >= 5, 1, 0)')).to be_nil
    end

    it 'does not trigger on <=' do
      expect(described_class.detect_equals_operator_hint('SI({x} <= 5, 1, 0)')).to be_nil
    end

    it 'does not trigger on !=' do
      expect(described_class.detect_equals_operator_hint('SI({x} != 5, 1, 0)')).to be_nil
    end

    it 'returns nil on blank expression' do
      expect(described_class.detect_equals_operator_hint('')).to be_nil
    end
  end
end
