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
  end
end
