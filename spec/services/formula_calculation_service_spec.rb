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

    # pf: non-régression — une formule qui référence juste un champ booléen
    # (checkbox, yes_no, ou formule booléenne) doit rendre "true"/"false",
    # pas "1"/"0". Le typage boolean doit se propager jusqu'à format_result.
    context 'single-reference boolean formulas' do
      let(:procedure) {
        create(:procedure, :published, types_de_champ_public: [
          { type: :checkbox, libelle: 'CaseACocher' },
          { type: :yes_no, libelle: 'OuiNon' },
          { type: :formule, libelle: 'FCheckbox' }, # expression: {CaseACocher}
          { type: :formule, libelle: 'FYesNo' }     # expression: {OuiNon}
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
            { type: :formule, libelle: 'Age' }
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

        it 'AGE returns empty string when date field is empty' do
          date_champ.update(value: '')
          # AGE(nil) retourne nil, sérialisé en string vide par format_result
          expect(compute_with('AGE({Date de naissance})')).to eq('')
        end

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
end
