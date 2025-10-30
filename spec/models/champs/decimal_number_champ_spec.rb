# frozen_string_literal: true

describe Champs::DecimalNumberChamp do
  let(:min) { nil }
  let(:max) { nil }
  let(:type_de_champ) { create(:type_de_champ, min:, max:) }

  let(:champ) { build(:champ_decimal_number, value:, type_de_champ:) }
  subject { champ.validate(:champs_public_value) }

  describe 'validation' do
    let(:champ) { Champs::DecimalNumberChamp.new(value:, dossier: build(:dossier)) }
    before do
      allow(champ).to receive(:type_de_champ).and_return(type_de_champ)
      allow(champ).to receive(:visible?).and_return(true)
      allow(champ).to receive(:in_dossier_revision?).and_return(true)
      allow(champ).to receive(:is_same_type_as_revision?).and_return(true)
      allow(champ).to receive(:in_dossier_stream?).and_return(true)
      allow(champ).to receive(:row?).and_return(false)
      allow(champ).to receive(:in_discarded_row?).and_return(false)
      champ.run_callbacks(:validation)
    end
    subject { champ.validate(:champs_public_value) }

    context 'when the value is integer number' do
      let(:value) { 2 }

      it { is_expected.to be_truthy }
    end

    context 'when the value is decimal number' do
      let(:value) { 2.6 }

      it { is_expected.to be_truthy }
    end

    context 'when the value is not a number' do
      let(:value) { 'toto' }

      it 'is not valid and contains expected error' do
        expect(subject).to be_falsey
        expect(champ.errors[:value]).to eq(["n'est pas un nombre", "doit comprendre entre 1 et 3 chiffres après le point"])
      end
    end

    context 'when value contain space' do
      before { champ.run_callbacks(:validation) }
      let(:value) { ' 2.6666 ' }
      it { expect(champ.value).to eq('2.6666') }
    end

    context 'when the value has too many decimal' do
      let(:value) { '2.6666' }

      it 'is not valid and contains expected error' do
        expect(subject).to be_falsey
        expect(champ.errors[:value]).to eq(["doit comprendre entre 1 et 3 chiffres après le point"])
      end
    end

    context 'when the value is blank' do
      let(:value) { '' }

      it { is_expected.to be_truthy }
    end

    context 'when the value is nil' do
      let(:value) { nil }

      it { is_expected.to be_truthy }
    end

    context 'when the value is negative' do
      context 'negative values are accepted' do
        let(:value) { -0.5 }

        it { is_expected.to be_truthy }
      end

      context 'negative values are not accepted' do
        before { champ.type_de_champ.update(options: { positive_number: '1' }) }
        let(:value) { -0.5 }

        it 'is not valid and contains errors' do
          is_expected.to be_falsey
          expect(champ.errors[:value]).to eq(["doit être un nombre positif"])
        end
      end
    end

    context 'when there is a range' do
      before { champ.type_de_champ.update(options: { range_number: '1', min_number: '2.5', max_number: '18' }) }
      context 'the value is in the range' do
        let(:value) { 4.5 }

        it { is_expected.to be_truthy }
      end

      context 'the value is not in the range' do
        let(:value) { 19 }

        it 'is not valid and contains errors' do
          is_expected.to be_falsey
          expect(champ.errors[:value]).to eq(["doit être un nombre compris entre 2.5 et 18.0"])
        end
      end

      context 'the value is bigger than max' do
        before { champ.type_de_champ.update(options: { range_number: '1', min_number: '', max_number: '18.5' }) }
        let(:value) { 19.5 }

        it 'is not valid and contains errors' do
          is_expected.to be_falsey
          expect(champ.errors[:value]).to eq(["doit être un nombre inférieur ou égal à 18.5"])
        end
      end

      context 'the value is smaller than min' do
        before { champ.type_de_champ.update(options: { range_number: '1', min_number: '2.3', max_number: '' }) }
        let(:value) { 1.5 }

        it 'is not valid and contains errors' do
          is_expected.to be_falsey
          expect(champ.errors[:value]).to eq(["doit être un nombre supérieur ou égal à 2.3"])
        end
      end

      context 'the range is not activated' do
        before { champ.type_de_champ.update(options: { range_number: '0', min_number: '2', max_number: '18' }) }
        let(:value) { 19 }

        it { is_expected.to be_truthy }
      end

      context 'the range is activated but min and max values are not defined' do
        before { champ.type_de_champ.update(options: { range_number: '0', min_number: '', max_number: '' }) }
        let(:value) { 19 }

        it { is_expected.to be_truthy }
      end
    end

    context 'when the champ is private, value is invalid, but validation is public' do
      let(:champ) { Champs::DecimalNumberChamp.new(value:, private: true, dossier: build(:dossier)) }
      let(:value) { '2.6666' }
      it { is_expected.to be_truthy }
    end

    context "when max is specified" do
      let(:max) { 10 }
      context 'when the value is equal to max' do
        let(:value) { '10' }

        it { is_expected.to be_truthy }
      end

      context 'when the value is greater than max' do
        let(:value) { 11 }

        it 'is not valid and contains expected error' do
          expect(subject).to be_falsey
          expect(champ.errors[:value]).to eq(["doit être inférieur ou égal à 10"])
        end
      end
    end

    context "when min is specified" do
     let(:min) { 10 }
     context 'when the value is equal to min' do
       let(:value) { '10' }

       it { is_expected.to be_truthy }
     end

     context 'when the value is less than min' do
       let(:value) { 9 }

       it 'is not valid and contains expected error' do
         expect(subject).to be_falsey
         expect(champ.errors[:value]).to eq(["doit être supérieur ou égal à 10"])
       end
     end
   end
  end

  describe 'for_export' do
    let(:champ) { Champs::DecimalNumberChamp.new(value:) }
    before { allow(champ).to receive(:type_de_champ).and_return(build(:type_de_champ_decimal_number)) }
    subject { champ.type_de_champ.champ_value_for_export(champ) }
    context 'with nil' do
      let(:value) { 0 }
      it { is_expected.to eq(0.0) }
    end
    context 'with simple number' do
      let(:value) { "120" }
      it { is_expected.to eq(120) }
    end
    context 'with number having spaces' do
      let(:value) { " 120 " }
      it { is_expected.to eq(120) }
    end
  end
end
