# frozen_string_literal: true

describe TypesDeChamp::FormuleTypeDeChamp do
  let(:type_de_champ) { build(:type_de_champ_formule, formule_expression: expression) }
  let(:formule_type_de_champ) { TypesDeChamp::FormuleTypeDeChamp.new(type_de_champ) }

  describe 'validation' do
    context 'with valid expression' do
      let(:expression) { '1 + 1' }

      it 'is valid' do
        expect(formule_type_de_champ).to be_valid
        expect(type_de_champ).to be_valid
      end
    end

    context 'with simple field reference' do
      let(:expression) { '{Montant HT} * 1.20' }

      it 'is valid' do
        expect(formule_type_de_champ).to be_valid
        expect(type_de_champ).to be_valid
      end
    end

    context 'with text formula' do
      let(:expression) { 'CONCAT({Prénom}, " ", {Nom})' }

      it 'is valid' do
        expect(formule_type_de_champ).to be_valid
        expect(type_de_champ).to be_valid
      end
    end

    context 'with too long expression' do
      let(:expression) { 'A' * 1001 }

      it 'is invalid' do
        expect(type_de_champ).not_to be_valid
        expect(type_de_champ.errors[:formule_expression]).to be_present
      end
    end

    context 'with invalid field reference' do
      let(:expression) { '{}' }

      it 'is invalid' do
        expect(type_de_champ).not_to be_valid
        expect(type_de_champ.errors[:formule_expression]).to be_present
      end
    end

    context 'with blank expression' do
      let(:expression) { '' }

      it 'is valid' do
        expect(formule_type_de_champ).to be_valid
        expect(type_de_champ).to be_valid
      end
    end
  end

  describe '#infer_output_type' do
    context 'with arithmetic expression' do
      let(:expression) { '1 + 2' }

      it 'infers number' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('number')
      end
    end

    context 'with comparison' do
      let(:expression) { '{Montant} > 1000' }

      it 'infers boolean' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('boolean')
      end
    end

    context 'with logical function ET' do
      let(:expression) { 'ET({x} > 5, {x} < 100)' }

      it 'infers boolean' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('boolean')
      end
    end

    context 'with SI returning number' do
      let(:expression) { 'SI({x} > 0, 1, 0)' }

      it 'infers number (type of the true branch)' do
        type_de_champ.valid?
        expect(type_de_champ.formule_output_type).to eq('number')
      end
    end

    context 'with blank expression' do
      let(:expression) { '' }

      it 'does not set output type' do
        formule_type_de_champ
        expect(type_de_champ.formule_output_type).to be_nil
      end
    end
  end

  describe '#estimated_fill_duration' do
    let(:expression) { '1 + 1' }
    let(:revision) { build(:procedure_revision) }

    it 'returns 0 seconds as formule fields are not fillable' do
      expect(formule_type_de_champ.estimated_fill_duration(revision)).to eq(0.seconds)
    end
  end
end
