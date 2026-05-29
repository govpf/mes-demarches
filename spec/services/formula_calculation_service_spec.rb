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
          { type: :formule, libelle: 'Total TTC' },
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

    # pf: étape H du chantier agrégat — alias FR additionnels.
    context 'alias FR additionnels (NB, COMPTE, RACINE, PLANCHER, PLAFOND, MEDIANE, JOINDRE)' do
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      def compute(expression)
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: expression))
        service.compute_value(formule_champ)
      end

      it 'NB compte les arguments' do
        expect(compute('NB(1, 2, 3)')).to eq('3')
      end

      it 'COMPTE est un synonyme de NB' do
        expect(compute('COMPTE(1, 2, 3, 4)')).to eq('4')
      end

      it 'RACINE calcule la racine carrée' do
        expect(compute('RACINE(16)')).to eq('4')
      end

      it 'PLANCHER arrondit vers le bas (floor)' do
        expect(compute('PLANCHER(3.7)')).to eq('3')
      end

      it 'PLAFOND arrondit vers le haut (ceil)' do
        expect(compute('PLAFOND(3.2)')).to eq('4')
      end

      it 'MEDIANE (nombre impair de valeurs) retourne la valeur centrale' do
        expect(compute('MEDIANE(1, 2, 3, 4, 5)')).to eq('3')
      end

      it 'MEDIANE (nombre pair de valeurs) retourne la moyenne des deux centrales' do
        expect(compute('MEDIANE(1, 2, 3, 4)')).to eq('2.5')
      end

      # pf: JOINDRE(array, separator) — testé en contexte agrégat (son usage
      # réel : JOINDRE({bloc/sous-champ}, ", ")), cf. describe agrégation.
    end

    context 'ARRONDI_INF, ARRONDI_SUP, ENTIER functions' do
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      def compute(expression)
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: expression))
        service.compute_value(formule_champ)
      end

      # ARRONDI_INF (floor)
      it 'ARRONDI_INF floors a positive non-integer' do
        expect(compute('ARRONDI_INF(3.7)')).to eq('3')
      end

      it 'ARRONDI_INF floors a negative non-integer' do
        expect(compute('ARRONDI_INF(-3.2)')).to eq('-4')
      end

      it 'ARRONDI_INF is a no-op on an exact integer' do
        expect(compute('ARRONDI_INF(5)')).to eq('5')
      end

      # ARRONDI_SUP (ceil)
      it 'ARRONDI_SUP ceils a positive non-integer' do
        expect(compute('ARRONDI_SUP(3.2)')).to eq('4')
      end

      it 'ARRONDI_SUP ceils a negative non-integer' do
        expect(compute('ARRONDI_SUP(-3.7)')).to eq('-3')
      end

      it 'ARRONDI_SUP is a no-op on an exact integer' do
        expect(compute('ARRONDI_SUP(5)')).to eq('5')
      end

      # ENTIER (truncation toward zero)
      it 'ENTIER truncates a positive non-integer toward zero' do
        expect(compute('ENTIER(3.7)')).to eq('3')
      end

      it 'ENTIER truncates a negative non-integer toward zero' do
        expect(compute('ENTIER(-3.7)')).to eq('-3')
      end

      it 'ENTIER is a no-op on an exact integer' do
        expect(compute('ENTIER(5)')).to eq('5')
      end

      it 'ENTIER on zero returns zero' do
        expect(compute('ENTIER(0)')).to eq('0')
      end

      # Cross-check: floor vs truncation differ for negatives
      it 'ARRONDI_INF and ENTIER differ for negative non-integers' do
        floor_result    = compute('ARRONDI_INF(-3.5)')
        truncate_result = compute('ENTIER(-3.5)')
        expect(floor_result).to    eq('-4')
        expect(truncate_result).to eq('-3')
        expect(floor_result).not_to eq(truncate_result)
      end
    end

    context 'ET/OU/NON functions with real procedure and revision' do
      let(:procedure) {
        create(:procedure, :published, types_de_champ_public: [
          { type: :integer_number, libelle: 'Prix 1' },
          { type: :integer_number, libelle: 'Prix 2' },
          { type: :integer_number, libelle: 'Prix 3' },
          { type: :formule, libelle: 'Résultat' },
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

      # pf: Sémantique Ruby pure — seuls false/nil sont falsy. L'admin écrit
      # explicitement la condition de comparaison `{Prix 1} > 0`, plutôt que
      # de compter sur 0 traité comme falsy à la Excel.
      it 'ET requires explicit comparison (zero is truthy in Ruby semantics)' do
        prix1 = dossier.project_champs_public.first
        prix1.update(value: '0')
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(ET({Prix 1} > 0, {Prix 2} > 100), "OK", "KO")', procedure.active_revision)
        formule.type_de_champ.update(formule_expression: expr)
        expect(service.compute_value(formule)).to eq('KO')
      end

      it 'OU requires explicit comparison and passes if at least one is true' do
        prix1 = dossier.project_champs_public.first
        prix1.update(value: '0')
        formule = dossier.project_champs_public.last
        expr, _deps = FormulaExpressionService.convert_to_stable_ids('SI(OU({Prix 1} > 0, {Prix 2} > 100), "OK", "KO")', procedure.active_revision)
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
        # Erreur capturée → message d'erreur, OU silent nil → nil, OU "" si l'expression
        # se révèle valide pour Dentaku après parsing.
        expect(result).to include('Erreur').or include('erreur').or be_nil.or be_empty
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
          { type: :formule, libelle: 'Résultat' },
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
          { type: :formule, libelle: 'Label' }, # sera défini comme SI({Majeur}, "adulte", "mineur")
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

    # pf: non-régression — une formule qui retourne un entier (ex: ARRONDI(x, 0)
    # ou un simple {champ_entier}) ne doit PAS introduire un "x.0" quand elle
    # est référencée par une autre formule. format_value_for_dentaku case :decimal
    # doit préserver le type Integer si la valeur stockée est sans décimale.
    context 'when a formula references another numeric formula that returned an integer' do
      let(:procedure) {
        create(:procedure, :published, types_de_champ_public: [
          { type: :decimal_number, libelle: 'X' },
          { type: :formule, libelle: 'Rounded' }, # ARRONDI({X}, 0)
          { type: :formule, libelle: 'Label' }, # CONCATENER("00", {Rounded}, "000")
        ])
      }
      let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }
      let(:x_champ) { dossier.project_champs_public[0] }
      let(:rounded_champ) { dossier.project_champs_public[1] }
      let(:label_champ) { dossier.project_champs_public[2] }
      let(:service) { described_class.new(dossier, locale: :fr) }

      before do
        expr_r, _ = FormulaExpressionService.convert_to_stable_ids('ARRONDI({X}, 0)', procedure.active_revision)
        rounded_champ.type_de_champ.update(formule_expression: expr_r)
        rounded_champ.type_de_champ.valid?
        rounded_champ.type_de_champ.save!

        expr_l, _ = FormulaExpressionService.convert_to_stable_ids('CONCATENER("00", {Rounded}, "000")', procedure.active_revision)
        label_champ.type_de_champ.update(formule_expression: expr_l)
      end

      it 'does not introduce a ".0" artifact when concatenating a formula that returned an integer' do
        x_champ.update(value: '3.7')
        rounded_champ.update(value: service.compute_value(rounded_champ)) # "4"
        expect(rounded_champ.reload.value).to eq('4')
        expect(service.compute_value(label_champ)).to eq('004000')
      end

      it 'preserves the decimal when the upstream formula actually returns a decimal' do
        x_champ.update(value: '3.74')
        # une formule décimale réelle ne doit pas perdre ses décimales
        decimal_expr, _ = FormulaExpressionService.convert_to_stable_ids('{X} * 2', procedure.active_revision)
        rounded_champ.type_de_champ.update(formule_expression: decimal_expr)
        rounded_champ.update(value: service.compute_value(rounded_champ)) # "7.48"
        expect(rounded_champ.reload.value).to eq('7.48')
        expect(service.compute_value(label_champ)).to eq('007.48000')
      end
    end

    # pf: non-régression — une formule qui référence juste un champ booléen
    # (checkbox, yes_no, ou formule booléenne) doit rendre "true"/"false",
    # pas "1"/"0". Le typage boolean doit se propager jusqu'à format_result.
    context 'single-reference boolean formulas' do
      let(:procedure) {
        create(:procedure, :published, types_de_champ_public: [
          { type: :checkbox, libelle: 'CaseACocher' },
          { type: :yes_no, libelle: 'OuiNon' },
          { type: :formule, libelle: 'FCheckbox' }, # expression: {CaseACocher}
          { type: :formule, libelle: 'FYesNo' }, # expression: {OuiNon}
        ])
      }
      let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }
      let(:case_champ) { dossier.project_champs_public[0] }
      let(:ouinon_champ) { dossier.project_champs_public[1] }
      let(:f_checkbox) { dossier.project_champs_public[2] }
      let(:f_ouinon) { dossier.project_champs_public[3] }
      let(:service) { described_class.new(dossier, locale: :fr) }

      before do
        expr1, _ = FormulaExpressionService.convert_to_stable_ids('{CaseACocher}', procedure.active_revision)
        f_checkbox.type_de_champ.update(formule_expression: expr1)
        expr2, _ = FormulaExpressionService.convert_to_stable_ids('{OuiNon}', procedure.active_revision)
        f_ouinon.type_de_champ.update(formule_expression: expr2)
      end

      it '{CaseACocher} returns "true" when checked' do
        case_champ.update!(value: 'true')
        expect(service.compute_value(f_checkbox)).to eq('true')
      end

      it '{CaseACocher} returns "false" when unchecked' do
        case_champ.update!(value: 'false')
        expect(service.compute_value(f_checkbox)).to eq('false')
      end

      it '{OuiNon} returns "true" when yes' do
        ouinon_champ.update!(value: 'true')
        expect(service.compute_value(f_ouinon)).to eq('true')
      end

      # pf: transitivité — une formule qui référence une formule booléenne
      # doit elle-même renvoyer "true"/"false", pas "0"/"1".
      it 'chained boolean formula: {FCheckbox} preserves boolean type' do
        case_champ.update!(value: 'true')
        # Calcule et stocke FCheckbox
        f_checkbox.update!(value: service.compute_value(f_checkbox))
        # Inférence du type de sortie de FCheckbox (boolean via la référence nue)
        f_checkbox.type_de_champ.valid?
        f_checkbox.type_de_champ.save!

        # Maintenant, une formule qui référence FCheckbox
        expr_chain, _ = FormulaExpressionService.convert_to_stable_ids('{FCheckbox}', procedure.active_revision)
        f_ouinon.type_de_champ.update(formule_expression: expr_chain)
        f_ouinon.type_de_champ.valid?
        f_ouinon.type_de_champ.save!

        expect(service.compute_value(f_ouinon)).to eq('true')
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

    # pf: Fonctions de date FR + natives Dentaku (DURATION).
    # Les champs date sont passés à Dentaku comme objets Date/DateTime natifs.
    context 'with French date functions' do
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }
      let(:service) { described_class.new(dossier, locale: :fr) }

      def compute(expression)
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: expression))
        service.compute_value(formule_champ)
      end

      describe 'AUJOURDHUI / MAINTENANT' do
        it 'AUJOURDHUI returns the current date as ISO 8601' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('AUJOURDHUI()')).to eq('2026-04-19')
          end
        end

        it 'MAINTENANT returns the current datetime as ISO 8601' do
          expect(compute('MAINTENANT()')).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        end
      end

      describe 'extraction JOUR / MOIS / ANNEE / JOURSEM' do
        it 'JOUR extracts the day' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('JOUR(AUJOURDHUI())')).to eq('19')
          end
        end

        it 'MOIS extracts the month' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('MOIS(AUJOURDHUI())')).to eq('4')
          end
        end

        it 'ANNEE extracts the year' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('ANNEE(AUJOURDHUI())')).to eq('2026')
          end
        end

        it 'JOURSEM returns ISO 8601 weekday (monday = 1)' do
          # 2026-04-20 = lundi
          travel_to Time.zone.local(2026, 4, 20) do
            expect(compute('JOURSEM(AUJOURDHUI())')).to eq('1')
          end
        end
      end

      describe 'EST_PASSEE / EST_FUTURE' do
        it 'EST_PASSEE returns true for yesterday' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('EST_PASSEE(AUJOURDHUI() - DUREE_JOURS(1))')).to eq('true')
          end
        end

        it 'EST_PASSEE returns false for tomorrow' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('EST_PASSEE(AUJOURDHUI() + DUREE_JOURS(1))')).to eq('false')
          end
        end

        it 'EST_FUTURE returns true for tomorrow' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('EST_FUTURE(AUJOURDHUI() + DUREE_JOURS(1))')).to eq('true')
          end
        end

        it 'EST_FUTURE returns false for yesterday' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('EST_FUTURE(AUJOURDHUI() - DUREE_JOURS(1))')).to eq('false')
          end
        end
      end

      describe 'AGE' do
        it 'AGE computes years elapsed when anniversary has passed' do
          travel_to Time.zone.local(2026, 6, 1) do
            expect(compute('AGE(AUJOURDHUI() - DUREE_ANNEES(36) - DUREE_JOURS(17))')).to eq('36')
          end
        end

        it 'AGE subtracts one when anniversary has not yet occurred this year' do
          travel_to Time.zone.local(2026, 4, 19) do
            # Né demain, donc anniv pas encore passé cette année → 35 au lieu de 36
            expect(compute('AGE(AUJOURDHUI() - DUREE_ANNEES(36) + DUREE_JOURS(1))')).to eq('35')
          end
        end
      end

      describe 'DUREE_ANNEES / DUREE_MOIS / DUREE_JOURS' do
        it 'Date + DUREE_ANNEES adds years' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('AUJOURDHUI() + DUREE_ANNEES(5)')).to eq('2031-04-19')
          end
        end

        it 'Date + DUREE_MOIS adds months' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('AUJOURDHUI() + DUREE_MOIS(3)')).to eq('2026-07-19')
          end
        end

        it 'Date + DUREE_JOURS adds days' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('AUJOURDHUI() + DUREE_JOURS(10)')).to eq('2026-04-29')
          end
        end

        it 'Date - DUREE_ANNEES subtracts years' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('AUJOURDHUI() - DUREE_ANNEES(1)')).to eq('2025-04-19')
          end
        end
      end

      describe 'DUREE_SEMAINES' do
        it 'Date + DUREE_SEMAINES adds n * 7 days' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('AUJOURDHUI() + DUREE_SEMAINES(2)')).to eq('2026-05-03')
          end
        end

        it 'Date - DUREE_SEMAINES subtracts n * 7 days' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('AUJOURDHUI() - DUREE_SEMAINES(1)')).to eq('2026-04-12')
          end
        end
      end

      describe 'JOURS_ENTRE / SEMAINES_ENTRE / MOIS_ENTRE / ANNEES_ENTRE' do
        it 'JOURS_ENTRE returns the day difference' do
          expect(compute('JOURS_ENTRE(AUJOURDHUI(), AUJOURDHUI() + DUREE_JOURS(10))')).to eq('10')
        end

        it 'JOURS_ENTRE can be negative when d2 is before d1' do
          expect(compute('JOURS_ENTRE(AUJOURDHUI(), AUJOURDHUI() - DUREE_JOURS(3))')).to eq('-3')
        end

        it 'SEMAINES_ENTRE returns integer weeks (truncated toward zero)' do
          # 13 jours → 1 semaine
          expect(compute('SEMAINES_ENTRE(AUJOURDHUI(), AUJOURDHUI() + DUREE_JOURS(13))')).to eq('1')
          # 14 jours → 2 semaines
          expect(compute('SEMAINES_ENTRE(AUJOURDHUI(), AUJOURDHUI() + DUREE_JOURS(14))')).to eq('2')
        end

        it 'SEMAINES_ENTRE truncates toward zero on negative ranges' do
          # -5 jours → 0 semaine (et pas -1 comme le ferait la division entière Ruby)
          expect(compute('SEMAINES_ENTRE(AUJOURDHUI(), AUJOURDHUI() - DUREE_JOURS(5))')).to eq('0')
          # -13 jours → -1 semaine
          expect(compute('SEMAINES_ENTRE(AUJOURDHUI(), AUJOURDHUI() - DUREE_JOURS(13))')).to eq('-1')
        end

        it 'MOIS_ENTRE handles month boundary (31 jan → 28 feb = 1 month)' do
          travel_to Time.zone.local(2026, 1, 31) do
            expect(compute('MOIS_ENTRE(AUJOURDHUI(), AUJOURDHUI() + DUREE_JOURS(28))')).to eq('1')
          end
        end

        it 'MOIS_ENTRE returns 12 across a full year' do
          travel_to Time.zone.local(2026, 1, 1) do
            expect(compute('MOIS_ENTRE(AUJOURDHUI(), AUJOURDHUI() + DUREE_ANNEES(1))')).to eq('12')
          end
        end

        it 'ANNEES_ENTRE handles 29 feb leap-year edge (anniversary not yet passed)' do
          # d1 = 2020-02-29, d2 = 2024-02-28 → 3 ans (anniv pas encore atteint)
          travel_to Time.zone.local(2020, 2, 29) do
            expect(compute('ANNEES_ENTRE(AUJOURDHUI(), AUJOURDHUI() + DUREE_ANNEES(4) - DUREE_JOURS(1))')).to eq('3')
          end
        end

        it 'ANNEES_ENTRE returns 4 once the anniversary is reached' do
          # d1 = 2020-02-29, d2 = 2024-02-29 → 4 ans
          travel_to Time.zone.local(2020, 2, 29) do
            expect(compute('ANNEES_ENTRE(AUJOURDHUI(), AUJOURDHUI() + DUREE_ANNEES(4))')).to eq('4')
          end
        end

        it 'ANNEES_ENTRE is symmetric: f(a, b) == -f(b, a)' do
          # d1 = 2020-02-28, d2 = 2024-02-29 → 4 ans
          # Inversé : d1 = 2024-02-29, d2 = 2020-02-28 → -4 ans (pas -5)
          travel_to Time.zone.local(2020, 2, 28) do
            expect(compute('ANNEES_ENTRE(AUJOURDHUI(), AUJOURDHUI() + DUREE_ANNEES(4) + DUREE_JOURS(1))')).to eq('4')
          end
          travel_to Time.zone.local(2024, 2, 29) do
            expect(compute('ANNEES_ENTRE(AUJOURDHUI(), AUJOURDHUI() - DUREE_ANNEES(4) - DUREE_JOURS(1))')).to eq('-4')
          end
        end
      end

      describe 'DURATION (native Dentaku)' do
        it 'exposes DURATION natively with years/months/days identifiers' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('AUJOURDHUI() + DURATION(1, years)')).to eq('2027-04-19')
            expect(compute('AUJOURDHUI() + DURATION(6, months)')).to eq('2026-10-19')
            expect(compute('AUJOURDHUI() + DURATION(7, days)')).to eq('2026-04-26')
          end
        end
      end

      describe 'Date arithmetic (Date - Date, comparisons)' do
        it 'Date - Date returns number of days' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('AUJOURDHUI() - (AUJOURDHUI() - DUREE_JOURS(7))')).to eq('7')
          end
        end

        it 'Date comparisons work' do
          travel_to Time.zone.local(2026, 4, 19) do
            expect(compute('AUJOURDHUI() > AUJOURDHUI() - DUREE_JOURS(1)')).to eq('true')
            expect(compute('AUJOURDHUI() < AUJOURDHUI() + DUREE_JOURS(1)')).to eq('true')
          end
        end
      end

      context 'with a date field reference' do
        let(:procedure) {
          create(:procedure, :published, types_de_champ_public: [
            { type: :date, libelle: 'Date de naissance' },
            { type: :formule, libelle: 'Age' },
          ])
        }
        let(:dossier) { create(:dossier, :with_populated_champs, procedure: procedure) }
        let(:date_champ) { dossier.project_champs_public[0] }
        let(:formule)    { dossier.project_champs_public[1] }
        let(:service)    { described_class.new(dossier, locale: :fr) }

        def compute_with(expression)
          expr, _deps = FormulaExpressionService.convert_to_stable_ids(expression, procedure.active_revision)
          formule.type_de_champ.update(formule_expression: expr)
          service.compute_value(formule)
        end

        it 'computes AGE from a date field' do
          travel_to Time.zone.local(2026, 4, 19) do
            date_champ.update(value: '1990-05-15')
            # Anniversaire du 15 mai pas encore passé au 19 avril 2026
            expect(compute_with('AGE({Date de naissance})')).to eq('35')
          end
        end

        it 'ANNEE extracts year from a date field' do
          date_champ.update(value: '1990-05-15')
          expect(compute_with('ANNEE({Date de naissance})')).to eq('1990')
        end

        it 'Date field + DUREE_ANNEES works' do
          date_champ.update(value: '1990-05-15')
          expect(compute_with('{Date de naissance} + DUREE_ANNEES(18)')).to eq('2008-05-15')
        end

        it 'EST_PASSEE on a past date field returns true' do
          date_champ.update(value: '1990-05-15')
          expect(compute_with('EST_PASSEE({Date de naissance})')).to eq('true')
        end

        # pf: spec retiré — redondant avec '#compute_value with formula returning nil'
        # qui couvre directement le cas AGE(nil) → nil. La distinction nil vs ""
        # est portée au niveau du service, pas du compute_with intégration.

        it 'EST_PASSEE on an empty date field returns false (no crash)' do
          date_champ.update(value: '')
          expect(compute_with('EST_PASSEE({Date de naissance})')).to eq('false')
        end
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

  # pf: Non-regression — les fonctions FR (SI, ARRONDI, SOMME, AGE…) sont des
  # noms d'API stables stockés en DB, pas des éléments d'UI. Elles doivent
  # être disponibles peu importe la locale d'affichage de l'utilisateur qui
  # consulte le dossier (sinon : un instructeur en UI anglaise voyait toutes
  # les formules retourner nil silencieusement).
  describe '.new_calculator (locale-agnostic)' do
    [:fr, :en, :de, nil, 'fr-FR'].each do |locale|
      it "registers French functions even with locale=#{locale.inspect}" do
        calc = described_class.new_calculator(locale: locale)
        result = calc.evaluate('ARRONDI(SI(x > 0, x * 1.16, 0))', x: 200)
        expect(result).to eq(232)
      end
    end
  end

  # pf: Quand Dentaku.evaluate retourne nil silencieusement (échec d'évaluation
  # type mismatch, fonction inconnue, etc.), compute_value propage ce nil
  # au lieu de le convertir en "" via format_result. Permet à l'affichage
  # de distinguer "formule plantée" (nil) de "formule retournant chaîne
  # vide légitime" (""). Cas concret : AGE sur un champ date vide retourne
  # nil (cf. lambda AGE qui fait `next nil if birth.nil?`).
  describe '#compute_value with formula returning nil' do
    let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }
    let(:service) { described_class.new(dossier, locale: :fr) }

    it 'propagates nil from a custom function (AGE on nil)' do
      allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: 'AGE(d)'))
      # d not provided → AGE receives nil → returns nil → compute returns nil
      expect(service.compute_value(formule_champ)).to be_nil
    end
  end

  # pf: normalisation value_json + JSONPathColumn des types PF — les références
  # à sous-chemin {Champ/Path} étaient cassées en formule (resolve_with_path ne
  # consultait que le préfixe tdc<N>). Cf. branche normalize-pf-champs-value-json.
  describe '#compute_value with PF field sub-paths' do
    context 'Numéro DN / date_de_naissance' do
      let(:procedure) do
        create(:procedure, :published, types_de_champ_public: [
          { type: :numero_dn, libelle: 'DN' },
          { type: :formule, libelle: 'Annee' },
        ])
      end
      let(:dossier) { create(:dossier, procedure: procedure) }
      let(:revision) { procedure.active_revision }
      let(:dn_tdc) { revision.types_de_champ.find { _1.libelle == 'DN' } }
      let(:formule_tdc) { revision.types_de_champ.find { _1.libelle == 'Annee' } }
      let(:formule_champ) { dossier.project_champs_public.find { _1.stable_id == formule_tdc.stable_id } }
      let(:service) { described_class.new(dossier) }

      before do
        dossier.project_champs_public.find { _1.stable_id == dn_tdc.stable_id }
          .update!(value_json: { 'numero_dn' => '1234567', 'date_de_naissance' => '2015-06-15' })
        formule_tdc.update!(formule_expression: "ANNEE({tdc#{dn_tdc.stable_id}/date_de_naissance})")
      end

      it 'résout la date de naissance via JSONPathColumn et calcule' do
        expect(service.compute_value(formule_champ)).to eq('2015')
      end
    end

    context 'Commune de Polynésie / ile' do
      let(:sample) { APIGeo::API.communes_de_polynesie.find { !_1.start_with?('---') } }
      let(:procedure) do
        create(:procedure, :published, types_de_champ_public: [
          { type: :commune_de_polynesie, libelle: 'Commune' },
          { type: :formule, libelle: 'Ile' },
        ])
      end
      let(:dossier) { create(:dossier, procedure: procedure) }
      let(:revision) { procedure.active_revision }
      let(:com_tdc) { revision.types_de_champ.find { _1.libelle == 'Commune' } }
      let(:formule_tdc) { revision.types_de_champ.find { _1.libelle == 'Ile' } }
      let(:formule_champ) { dossier.project_champs_public.find { _1.stable_id == formule_tdc.stable_id } }
      let(:service) { described_class.new(dossier) }

      before do
        dossier.project_champs_public.find { _1.stable_id == com_tdc.stable_id }.update!(value: sample)
        formule_tdc.update!(formule_expression: "{tdc#{com_tdc.stable_id}/ile}")
      end

      it 'résout l\'île via le cache value_json et la JSONPathColumn' do
        city = APIGeo::API.commune_by_city_postal_code(sample)
        expect(service.compute_value(formule_champ)).to eq(city[:ile])
      end
    end
  end

  # pf: chantier formule-agrégat — une formule placée hors bloc peut agréger
  # un sous-champ de toutes les lignes via {bloc/sub}, ou compter le bloc
  # via {bloc}. Cf. docs/superpowers/specs/2026-05-21-formule-repetitions-design.md
  describe '#compute_value with aggregation over a repetition block' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        {
          type: :repetition, libelle: 'Lignes', mandatory: false, children: [
            { type: :text, libelle: 'Désignation' },
            { type: :integer_number, libelle: 'Prix HT' },
          ],
        },
        { type: :formule, libelle: 'Total' },
      ])
    end
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:revision) { procedure.active_revision }
    let(:bloc_tdc) { revision.types_de_champ.find { _1.libelle == 'Lignes' } }
    let(:prix_ht_tdc) { revision.types_de_champ.find { _1.libelle == 'Prix HT' } }
    let(:formule_tdc) { revision.types_de_champ.find { _1.libelle == 'Total' } }
    let(:formule_champ) { dossier.project_champs_public.find { _1.stable_id == formule_tdc.stable_id } }
    let(:service) { described_class.new(dossier) }

    def add_row_with_prix_ht(value)
      row_id = dossier.repetition_add_row(bloc_tdc, updated_by: 'test')
      if value
        # pf: repetition_add_row crée juste le RepetitionChamp pour le row_id ;
        # les sous-champs sont créés à la demande via champ_for_update.
        sub_champ = dossier.champ_for_update(prix_ht_tdc, row_id: row_id, updated_by: 'test')
        sub_champ.update!(value: value.to_s)
      end
      row_id
    end

    def set_formula(expression)
      formule_tdc.update!(formule_expression: expression)
    end

    def sub_ref
      "tdc#{bloc_tdc.stable_id}/sub_#{prix_ht_tdc.stable_id}"
    end

    def bloc_ref
      "tdc#{bloc_tdc.stable_id}"
    end

    context 'SOMME sur un sous-champ numérique' do
      before do
        add_row_with_prix_ht(100)
        add_row_with_prix_ht(200)
        add_row_with_prix_ht(50)
      end

      it 'somme les prix de toutes les lignes' do
        set_formula("SOMME({#{sub_ref}})")
        expect(service.compute_value(formule_champ)).to eq('350')
      end
    end

    context 'COUNT sur le bloc entier' do
      before do
        add_row_with_prix_ht(100)
        add_row_with_prix_ht(200)
        add_row_with_prix_ht(50)
      end

      it 'compte le nombre de lignes' do
        set_formula("COUNT({#{bloc_ref}})")
        expect(service.compute_value(formule_champ)).to eq('3')
      end
    end

    context 'JOINDRE sur un sous-champ texte (Désignation)' do
      let(:designation_tdc) { revision.types_de_champ.find { _1.libelle == 'Désignation' } }

      def add_row_with_designation(label)
        row_id = dossier.repetition_add_row(bloc_tdc, updated_by: 'test')
        dossier.champ_for_update(designation_tdc, row_id:, updated_by: 'test').update!(value: label)
        row_id
      end

      before do
        add_row_with_designation('Pommes')
        add_row_with_designation('Poires')
        add_row_with_designation('Bananes')
      end

      it 'concatène les désignations de toutes les lignes' do
        set_formula("JOINDRE({tdc#{bloc_tdc.stable_id}/sub_#{designation_tdc.stable_id}}, \", \")")
        expect(service.compute_value(formule_champ)).to eq('Pommes, Poires, Bananes')
      end
    end

    context 'MAX et MIN sur un sous-champ' do
      before do
        add_row_with_prix_ht(100)
        add_row_with_prix_ht(200)
        add_row_with_prix_ht(50)
      end

      it 'MAX retourne le plus grand' do
        set_formula("MAX({#{sub_ref}})")
        expect(service.compute_value(formule_champ)).to eq('200')
      end

      it 'MIN retourne le plus petit' do
        set_formula("MIN({#{sub_ref}})")
        expect(service.compute_value(formule_champ)).to eq('50')
      end
    end

    context 'MOYENNE sur un sous-champ' do
      before do
        add_row_with_prix_ht(100)
        add_row_with_prix_ht(200)
        add_row_with_prix_ht(150)
      end

      it 'retourne la moyenne arithmétique' do
        set_formula("MOYENNE({#{sub_ref}})")
        expect(service.compute_value(formule_champ)).to eq('150')
      end
    end

    context 'bloc vide' do
      it 'SOMME retourne 0' do
        set_formula("SOMME({#{sub_ref}})")
        expect(service.compute_value(formule_champ)).to eq('0')
      end

      it 'COUNT retourne 0' do
        set_formula("COUNT({#{bloc_ref}})")
        expect(service.compute_value(formule_champ)).to eq('0')
      end

      # pf: Dentaku natif MAX/[] = nil (cf. spec sentinelle dentaku_array_functions).
      # Le service propage le nil → champ formule reste vide (pas d'erreur).
      it 'MAX retourne nil (rien à comparer)' do
        set_formula("MAX({#{sub_ref}})")
        expect(service.compute_value(formule_champ)).to be_nil
      end
    end

    context 'ligne avec sous-champ vide' do
      before do
        add_row_with_prix_ht(100)
        add_row_with_prix_ht(nil) # ligne sans Prix HT saisi
        add_row_with_prix_ht(50)
      end

      it 'SOMME ignore les valeurs nil (somme les 2 lignes valides)' do
        set_formula("SOMME({#{sub_ref}})")
        expect(service.compute_value(formule_champ)).to eq('150')
      end

      it 'COUNT compte toutes les lignes (3) — la cardinalité ne dépend pas des nil' do
        set_formula("COUNT({#{bloc_ref}})")
        expect(service.compute_value(formule_champ)).to eq('3')
      end
    end

    context 'combinaison : reste à payer' do
      let(:procedure) do
        create(:procedure, :published, types_de_champ_public: [
          {
            type: :repetition, libelle: 'Lignes', mandatory: false, children: [
              { type: :integer_number, libelle: 'Prix HT' },
            ],
          },
          {
            type: :repetition, libelle: 'Paiements', mandatory: false, children: [
              { type: :integer_number, libelle: 'Montant' },
            ],
          },
          { type: :formule, libelle: 'Total' },
        ])
      end
      let(:paiement_tdc) { revision.types_de_champ.find { _1.libelle == 'Paiements' } }
      let(:montant_tdc) { revision.types_de_champ.find { _1.libelle == 'Montant' } }

      def add_paiement(value)
        row_id = dossier.repetition_add_row(paiement_tdc, updated_by: 'test')
        sub_champ = dossier.champ_for_update(montant_tdc, row_id: row_id, updated_by: 'test')
        sub_champ.update!(value: value.to_s)
      end

      it 'SOMME(lignes/prix) - SOMME(paiements/montant) = reste à payer' do
        add_row_with_prix_ht(100)
        add_row_with_prix_ht(200)
        add_paiement(150)

        sub_prix = "tdc#{bloc_tdc.stable_id}/sub_#{prix_ht_tdc.stable_id}"
        sub_montant = "tdc#{paiement_tdc.stable_id}/sub_#{montant_tdc.stable_id}"

        set_formula("SOMME({#{sub_prix}}) - SOMME({#{sub_montant}})")
        expect(service.compute_value(formule_champ)).to eq('150')
      end
    end

    # pf: agréger un sous-champ FORMULE (formule-ligne dans le bloc) — son
    # résultat est stocké en string, il faut le coercer selon formule_output_type
    # (sinon SOMME("200") = 0). Pattern du catalogue : transformation par ligne
    # via formule-ligne intermédiaire, puis agrégation extérieure.
    context 'agrégation sur un sous-champ formule-ligne' do
      let(:procedure) do
        create(:procedure, :published, types_de_champ_public: [
          {
            type: :repetition, libelle: 'Lignes', mandatory: false, children: [
              { type: :integer_number, libelle: 'Prix HT' },
              { type: :formule, libelle: 'Montant TTC' },
            ],
          },
          { type: :formule, libelle: 'Total TTC' },
        ])
      end
      let(:ligne_formule_tdc) { revision.types_de_champ.find { _1.libelle == 'Montant TTC' } }
      let(:total_tdc) { revision.types_de_champ.find { _1.libelle == 'Total TTC' } }
      let(:total_champ) { dossier.project_champs_public.find { _1.stable_id == total_tdc.stable_id } }

      before do
        ligne_formule_tdc.update!(formule_expression: "{tdc#{prix_ht_tdc.stable_id}} * 2")
        total_tdc.update!(formule_expression: "SOMME({tdc#{bloc_tdc.stable_id}/sub_#{ligne_formule_tdc.stable_id}})")
      end

      # pf: on NE crée PAS le champ formule-ligne (Montant TTC) : c'est le cas
      # réel — la cascade ne persiste pas les champs formule enfants d'un bloc
      # (return [] if tdc.child?), et en preview ils n'existent que matérialisés.
      # L'agrégat doit donc recalculer la formule-ligne à la volée par ligne.
      def add_row_with_prix(prix)
        row_id = dossier.repetition_add_row(bloc_tdc, updated_by: 'test')
        dossier.champ_for_update(prix_ht_tdc, row_id:, updated_by: 'test').update!(value: prix.to_s)
        row_id
      end

      it 'somme les résultats de la formule-ligne (non persistée) de chaque ligne' do
        add_row_with_prix(100) # Montant TTC = 200
        add_row_with_prix(50)  # Montant TTC = 100
        expect(service.compute_value(total_champ)).to eq('300')
      end
    end
  end
end
