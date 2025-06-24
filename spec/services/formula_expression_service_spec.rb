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

        expect(stable_expr).to eq('{123} * 1.2 + {456}')
        expect(dependencies).to match_array([123, 456])
      end
    end

    context 'with unknown field reference' do
      let(:expression) { '{Montant HT} + {Inexistant}' }

      it 'keeps unknown references as-is' do
        stable_expr, dependencies = FormulaExpressionService.convert_to_stable_ids(expression, revision)

        expect(stable_expr).to eq('{123} + {Inexistant}')
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

        expect(stable_expr).to eq('{123} + {456}')
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
end
