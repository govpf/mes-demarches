# frozen_string_literal: true

describe FormulaCalculationService do
  let(:dossier) { create(:dossier) }
  let(:service) { described_class.new(dossier) }

  describe '#compute_value' do
    context 'with simple arithmetic expressions' do
      let(:formule_champ) { create(:champ_formule, dossier: dossier, expression: '2 + 3') }

      it 'computes basic arithmetic' do
        expect(service.compute_value(formule_champ)).to eq('5')
      end
    end

    context 'with field references' do
      let!(:montant_champ) { create(:champ_integer_number, dossier: dossier, libelle: 'Montant HT', value: '1000') }
      let!(:taux_champ) { create(:champ_decimal_number, dossier: dossier, libelle: 'Taux TVA', value: '0.20') }
      let(:formule_champ) { create(:champ_formule, dossier: dossier, expression: '{Montant HT} * (1 + {Taux TVA})') }

      it 'resolves field references and computes' do
        expect(service.compute_value(formule_champ)).to eq('1200')
      end
    end

    context 'with French functions' do
      let!(:prix1_champ) { create(:champ_decimal_number, dossier: dossier, libelle: 'Prix 1', value: '100') }
      let!(:prix2_champ) { create(:champ_decimal_number, dossier: dossier, libelle: 'Prix 2', value: '200') }
      let!(:prix3_champ) { create(:champ_decimal_number, dossier: dossier, libelle: 'Prix 3', value: '150') }

      context 'when locale is French' do
        let(:service) { described_class.new(dossier, locale: :fr) }

        it 'supports SOMME function' do
          formule_champ = create(:champ_formule, dossier: dossier, expression: 'SOMME({Prix 1}, {Prix 2}, {Prix 3})')
          expect(service.compute_value(formule_champ)).to eq('450')
        end

        it 'supports MOYENNE function' do
          formule_champ = create(:champ_formule, dossier: dossier, expression: 'MOYENNE({Prix 1}, {Prix 2}, {Prix 3})')
          expect(service.compute_value(formule_champ)).to eq('150')
        end

        it 'supports SI function' do
          formule_champ = create(:champ_formule, dossier: dossier, expression: 'SI({Prix 1} > 50, {Prix 2}, {Prix 3})')
          expect(service.compute_value(formule_champ)).to eq('200')
        end
      end
    end

    context 'with different field types' do
      let!(:yes_no_champ) { create(:champ_yes_no, dossier: dossier, libelle: 'Eligible', value: 'true') }
      let!(:checkbox_champ) { create(:champ_checkbox, dossier: dossier, libelle: 'Accepte CGV', value: 'on') }
      let!(:date_champ) { create(:champ_date, dossier: dossier, libelle: 'Date debut', value: '2024-01-01') }

      it 'converts yes_no to numeric' do
        formule_champ = create(:champ_formule, dossier: dossier, expression: '{Eligible} * 100')
        expect(service.compute_value(formule_champ)).to eq('100')
      end

      it 'converts checkbox to numeric' do
        formule_champ = create(:champ_formule, dossier: dossier, expression: '{Accepte CGV} * 50')
        expect(service.compute_value(formule_champ)).to eq('50')
      end
    end

    context 'with text fields containing numbers' do
      let!(:text_champ) { create(:champ_text, dossier: dossier, libelle: 'Quantite', value: 'Il y a 25 éléments') }

      it 'extracts numbers from text' do
        formule_champ = create(:champ_formule, dossier: dossier, expression: '{Quantite} * 2')
        expect(service.compute_value(formule_champ)).to eq('50')
      end
    end

    context 'with empty or missing fields' do
      let!(:empty_champ) { create(:champ_integer_number, dossier: dossier, libelle: 'Vide', value: '') }
      let(:formule_champ) { create(:champ_formule, dossier: dossier, expression: '{Vide} + 10') }

      it 'treats empty fields as zero' do
        expect(service.compute_value(formule_champ)).to eq('10')
      end

      it 'handles missing field references' do
        formule_champ = create(:champ_formule, dossier: dossier, expression: '{Inexistant} + 5')
        expect(service.compute_value(formule_champ)).to include("Erreur : champ 'Inexistant' introuvable")
      end
    end

    context 'with circular references' do
      let!(:formule1) { create(:champ_formule, dossier: dossier, libelle: 'Formule A', expression: '{Formule B} + 1') }
      let!(:formule2) { create(:champ_formule, dossier: dossier, libelle: 'Formule B', expression: '{Formule A} + 1') }

      it 'detects circular references' do
        expect(service.compute_value(formule1)).to include('référence circulaire')
      end
    end

    context 'with syntax errors' do
      let(:formule_champ) { create(:champ_formule, dossier: dossier, expression: '2 + + 3') }

      it 'handles syntax errors gracefully' do
        expect(service.compute_value(formule_champ)).to include('Erreur de syntaxe')
      end
    end

    context 'with complex nested formulas' do
      let!(:base_champ) { create(:champ_integer_number, dossier: dossier, libelle: 'Base', value: '100') }
      let!(:formule_intermediate) { create(:champ_formule, dossier: dossier, libelle: 'Intermediate', expression: '{Base} * 2') }
      let(:formule_final) { create(:champ_formule, dossier: dossier, expression: '{Intermediate} + 50') }

      it 'handles nested formula calculations' do
        expect(service.compute_value(formule_final)).to eq('250')
      end
    end
  end
end
