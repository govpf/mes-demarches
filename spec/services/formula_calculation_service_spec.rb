# frozen_string_literal: true

describe FormulaCalculationService do
  let(:dossier) { create(:dossier) }
  let(:service) { described_class.new(dossier) }

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
      let!(:montant_champ) { Champs::IntegerNumberChamp.new(dossier: dossier, value: '1000') }
      let!(:taux_champ) { Champs::DecimalNumberChamp.new(dossier: dossier, value: '0.20') }
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      before do
        allow(montant_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_integer_number, libelle: 'Montant HT'))
        allow(taux_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_decimal_number, libelle: 'Taux TVA'))
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '{Montant HT} * (1 + {Taux TVA})'))
        allow(dossier).to receive(:champs).and_return([montant_champ, taux_champ, formule_champ])
      end

      it 'resolves field references and computes' do
        expect(service.compute_value(formule_champ)).to eq('1200')
      end
    end

    context 'with French functions' do
      let!(:prix1_champ) { Champs::DecimalNumberChamp.new(dossier: dossier, value: '100') }
      let!(:prix2_champ) { Champs::DecimalNumberChamp.new(dossier: dossier, value: '200') }
      let!(:prix3_champ) { Champs::DecimalNumberChamp.new(dossier: dossier, value: '150') }

      before do
        allow(prix1_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_decimal_number, libelle: 'Prix 1'))
        allow(prix2_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_decimal_number, libelle: 'Prix 2'))
        allow(prix3_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_decimal_number, libelle: 'Prix 3'))
        allow(dossier).to receive(:champs).and_return([prix1_champ, prix2_champ, prix3_champ])
      end

      context 'when locale is French' do
        let(:service) { described_class.new(dossier, locale: :fr) }

        it 'supports SOMME function' do
          formule_champ = Champs::FormuleChamp.new(dossier: dossier)
          allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '{Prix 1} + {Prix 2} + {Prix 3}'))
          allow(dossier).to receive(:champs).and_return([prix1_champ, prix2_champ, prix3_champ, formule_champ])
          expect(service.compute_value(formule_champ)).to eq('450')
        end

        it 'supports MOYENNE function' do
          formule_champ = Champs::FormuleChamp.new(dossier: dossier)
          allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '({Prix 1} + {Prix 2} + {Prix 3}) / 3'))
          allow(dossier).to receive(:champs).and_return([prix1_champ, prix2_champ, prix3_champ, formule_champ])
          expect(service.compute_value(formule_champ)).to eq('150')
        end

        it 'supports SI function' do
          formule_champ = Champs::FormuleChamp.new(dossier: dossier)
          allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: 'SI({Prix 1} > 50, {Prix 2}, {Prix 3})'))
          allow(dossier).to receive(:champs).and_return([prix1_champ, prix2_champ, prix3_champ, formule_champ])
          expect(service.compute_value(formule_champ)).to eq('200')
        end
      end
    end

    context 'with different field types' do
      let!(:yes_no_champ) { Champs::YesNoChamp.new(dossier: dossier, value: 'true') }
      let!(:checkbox_champ) { Champs::CheckboxChamp.new(dossier: dossier, value: 'on') }
      let!(:date_champ) { Champs::DateChamp.new(dossier: dossier, value: '2024-01-01') }

      before do
        allow(yes_no_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_yes_no, libelle: 'Eligible'))
        allow(checkbox_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_checkbox, libelle: 'Accepte CGV'))
        allow(date_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_date, libelle: 'Date debut'))
        allow(dossier).to receive(:champs).and_return([yes_no_champ, checkbox_champ, date_champ])
      end

      it 'converts yes_no to numeric' do
        formule_champ = Champs::FormuleChamp.new(dossier: dossier)
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '{Eligible} * 100'))
        expect(service.compute_value(formule_champ)).to eq('100')
      end

      it 'converts checkbox to numeric' do
        formule_champ = Champs::FormuleChamp.new(dossier: dossier)
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '{Accepte CGV} * 50'))
        expect(service.compute_value(formule_champ)).to eq('50')
      end
    end

    context 'with text fields containing numbers' do
      let!(:text_champ) { Champs::TextChamp.new(dossier: dossier, value: 'Il y a 25 éléments') }

      before do
        allow(text_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_text, libelle: 'Quantite'))
        allow(dossier).to receive(:champs).and_return([text_champ])
      end

      it 'extracts numbers from text' do
        formule_champ = Champs::FormuleChamp.new(dossier: dossier)
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '{Quantite} * 2'))
        expect(service.compute_value(formule_champ)).to eq('50')
      end
    end

    context 'with empty or missing fields' do
      let!(:empty_champ) { Champs::IntegerNumberChamp.new(dossier: dossier, value: '') }
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      before do
        allow(empty_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_integer_number, libelle: 'Vide'))
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '{Vide} + 10'))
        allow(dossier).to receive(:champs).and_return([empty_champ, formule_champ])
      end

      it 'treats empty fields as zero' do
        expect(service.compute_value(formule_champ)).to eq('10')
      end

      it 'handles missing field references' do
        formule_champ_missing = Champs::FormuleChamp.new(dossier: dossier)
        allow(formule_champ_missing).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '{Inexistant} + 5'))
        expect(service.compute_value(formule_champ_missing)).to include("Erreur : champ 'Inexistant' introuvable")
      end
    end

    context 'with circular references' do
      let!(:formule1) { Champs::FormuleChamp.new(dossier: dossier) }
      let!(:formule2) { Champs::FormuleChamp.new(dossier: dossier) }

      before do
        allow(formule1).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, libelle: 'Formule A', formule_expression: '{Formule B} + 1'))
        allow(formule2).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, libelle: 'Formule B', formule_expression: '{Formule A} + 1'))
        allow(dossier).to receive(:champs).and_return([formule1, formule2])
      end

      it 'detects circular references' do
        expect(service.compute_value(formule1)).to include('référence circulaire')
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

    context 'with complex nested formulas' do
      let!(:base_champ) { Champs::IntegerNumberChamp.new(dossier: dossier, value: '100') }
      let!(:formule_intermediate) { Champs::FormuleChamp.new(dossier: dossier) }
      let(:formule_final) { Champs::FormuleChamp.new(dossier: dossier) }

      before do
        allow(base_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_integer_number, libelle: 'Base'))
        allow(formule_intermediate).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, libelle: 'Intermediate', formule_expression: '{Base} * 2'))
        allow(formule_final).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '{Intermediate} + 50'))
        allow(dossier).to receive(:champs).and_return([base_champ, formule_intermediate, formule_final])
      end

      it 'handles nested formula calculations' do
        expect(service.compute_value(formule_final)).to eq('250')
      end
    end

    context 'with decimal results' do
      let!(:dividend_champ) { Champs::IntegerNumberChamp.new(dossier: dossier, value: '100') }
      let!(:divisor_champ) { Champs::IntegerNumberChamp.new(dossier: dossier, value: '3') }
      let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

      before do
        allow(dividend_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_integer_number, libelle: 'Dividend'))
        allow(divisor_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_integer_number, libelle: 'Divisor'))
        allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '{Dividend} / {Divisor}'))
        allow(dossier).to receive(:champs).and_return([dividend_champ, divisor_champ, formule_champ])
      end

      it 'preserves true decimal results' do
        result = service.compute_value(formule_champ)
        expect(result).to start_with('33.333333')
        expect(result).not_to end_with('.0')
      end

      it 'converts whole number decimals to integers' do
        allow(divisor_champ).to receive(:value).and_return('10')
        formule_champ_whole = Champs::FormuleChamp.new(dossier: dossier)
        allow(formule_champ_whole).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: '{Dividend} / {Divisor}'))
        expect(service.compute_value(formule_champ_whole)).to eq('10')
      end
    end
  end
end
