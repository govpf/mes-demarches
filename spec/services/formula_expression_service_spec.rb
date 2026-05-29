# frozen_string_literal: true

describe FormulaExpressionService do
  let(:procedure) { build(:procedure) }
  let(:revision) { procedure.active_revision }
  let(:montant_tdc) { build(:type_de_champ_integer_number, libelle: 'Montant HT', stable_id: 123) }
  let(:tva_tdc) { build(:type_de_champ_decimal_number, libelle: 'TVA', stable_id: 456) }

  before do
    allow(revision).to receive(:types_de_champ).and_return([montant_tdc, tva_tdc])
  end

  describe '.convert_to_stable_ids' do
    context 'with field references' do
      let(:expression) { '{Montant HT} * 1.2 + {TVA}' }

      it 'converts libelles to stable_ids' do
        stable_expr, dependencies = FormulaExpressionService.convert_to_stable_ids(expression, revision)

        expect(stable_expr).to eq('{tdc123} * 1.2 + {tdc456}')
        expect(dependencies).to match_array([123, 456])
      end
    end

    context 'with unknown field reference' do
      let(:expression) { '{Montant HT} + {Inexistant}' }

      it 'keeps unknown references as-is' do
        stable_expr, dependencies = FormulaExpressionService.convert_to_stable_ids(expression, revision)

        expect(stable_expr).to eq('{tdc123} + {Inexistant}')
        expect(dependencies).to eq([123])
      end
    end

    context 'with blank expression' do
      let(:expression) { '' }

      it 'returns empty values' do
        stable_expr, dependencies = FormulaExpressionService.convert_to_stable_ids(expression, revision)

        expect(stable_expr).to eq('')
        expect(dependencies).to eq([])
      end
    end

    context 'with case insensitive matching' do
      let(:expression) { '{montant ht} + {TVA}' }

      it 'matches case insensitively' do
        stable_expr, dependencies = FormulaExpressionService.convert_to_stable_ids(expression, revision)

        expect(stable_expr).to eq('{tdc123} + {tdc456}')
        expect(dependencies).to match_array([123, 456])
      end
    end
  end

  describe '.convert_to_libelles' do
    context 'with stable_id references' do
      let(:stable_expression) { '{123} * 1.2 + {456}' }

      it 'converts stable_ids to libelles' do
        result = FormulaExpressionService.convert_to_libelles(stable_expression, revision)

        expect(result).to eq('{Montant HT} * 1.2 + {TVA}')
      end
    end

    context 'with unknown stable_id' do
      let(:stable_expression) { '{123} + {999}' }

      it 'keeps unknown stable_ids as-is' do
        result = FormulaExpressionService.convert_to_libelles(stable_expression, revision)

        expect(result).to eq('{Montant HT} + {999}')
      end
    end

    context 'with blank expression' do
      let(:stable_expression) { '' }

      it 'returns empty string' do
        result = FormulaExpressionService.convert_to_libelles(stable_expression, revision)

        expect(result).to eq('')
      end
    end
  end

  describe 'roundtrip conversion' do
    let(:original_expression) { '{Montant HT} * 1.2 + {TVA} - 100' }

    it 'preserves the original expression through conversion cycle' do
      stable_expr, _deps = FormulaExpressionService.convert_to_stable_ids(original_expression, revision)
      result = FormulaExpressionService.convert_to_libelles(stable_expr, revision)

      expect(result).to eq(original_expression)
    end
  end

  # pf: Tests for conversion with sub-properties (paths)
  describe '.convert_to_libelles with paths' do
    let(:code_postal_tdc) { build(:type_de_champ, type_champ: :code_postal_de_polynesie, stable_id: 123, libelle: 'Code postal') }
    let(:dn_tdc) { build(:type_de_champ, type_champ: :numero_dn, stable_id: 456, libelle: 'DN') }
    let(:revision) { build(:procedure_revision) }

    before do
      allow(revision).to receive(:types_de_champ).and_return([code_postal_tdc, dn_tdc])
    end

    it 'converts {tdc123/commune} to {Commune}' do
      stable_expr = '{tdc123/commune}'
      result = FormulaExpressionService.convert_to_libelles(stable_expr, revision)

      expect(result).to eq('{Commune}')
    end

    it 'converts {tdc456/date_de_naissance} to {Date de naissance}' do
      stable_expr = '{tdc456/date_de_naissance}'
      result = FormulaExpressionService.convert_to_libelles(stable_expr, revision)

      expect(result).to eq('{Date de naissance}')
    end

    it 'preserves system columns unchanged' do
      stable_expr = '{dossier_number} + {individual_first_name}'
      result = FormulaExpressionService.convert_to_libelles(stable_expr, revision)

      expect(result).to eq(stable_expr)
    end

    it 'converts {tdc123} to {Code postal} (without path)' do
      stable_expr = '{tdc123}'
      result = FormulaExpressionService.convert_to_libelles(stable_expr, revision)

      expect(result).to eq('{Code postal}')
    end

    it 'supports mixed format in same expression' do
      stable_expr = '{tdc123/commune} + {tdc456} + {dossier_number}'
      result = FormulaExpressionService.convert_to_libelles(stable_expr, revision)

      expect(result).to eq('{Commune} + {DN} + {dossier_number}')
    end
  end

  # pf: agrégat sur bloc répétable — l'interne {tdc<bloc>/sub_<sub_id>} doit
  # se réafficher en {Bloc/Sous-champ} dans l'éditeur (sinon l'admin voit le brut).
  describe '.convert_to_libelles avec agrégat de bloc répétable' do
    let(:bloc_tdc) { build(:type_de_champ, type_champ: :repetition, stable_id: 100, libelle: 'Facture') }
    let(:prix_tdc) { build(:type_de_champ, type_champ: :integer_number, stable_id: 101, libelle: 'Prix HT') }
    let(:revision) { build(:procedure_revision) }

    before do
      allow(revision).to receive(:types_de_champ).and_return([bloc_tdc, prix_tdc])
    end

    it 'convertit {tdc100/sub_101} en {Facture/Prix HT}' do
      result = FormulaExpressionService.convert_to_libelles('SOMME({tdc100/sub_101})', revision)
      expect(result).to eq('SOMME({Facture/Prix HT})')
    end

    it 'convertit {tdc100} (bloc nu) en {Facture}' do
      result = FormulaExpressionService.convert_to_libelles('NB({tdc100})', revision)
      expect(result).to eq('NB({Facture})')
    end

    it 'laisse le brut si le sous-champ est inconnu' do
      result = FormulaExpressionService.convert_to_libelles('SOMME({tdc100/sub_99999})', revision)
      expect(result).to eq('SOMME({tdc100/sub_99999})')
    end
  end
end
