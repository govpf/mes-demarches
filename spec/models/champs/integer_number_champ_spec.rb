describe Champs::IntegerNumberChamp do
  let(:min) { nil }
  let(:max) { nil }
  let(:type_de_champ) { create(:type_de_champ, min:, max:) }

  let(:champ) { build(:champ_integer_number, value:, type_de_champ:) }
  subject { champ.validate(:champs_public_value) }

  describe '#valid?' do
    context 'when the value is integer number' do
      let(:value) { 2 }

      it { is_expected.to be_truthy }
    end

    context 'when the value is decimal number' do
      let(:value) { 2.6 }

      it 'is not valid and contains errors' do
        is_expected.to be_falsey
        expect(champ.errors[:value]).to eq(["doit être un nombre entier (sans chiffre après la virgule)"])
      end
    end

    context 'when the value is not a number' do
      let(:value) { 'toto' }

      it 'is not valid and contains errors' do
        is_expected.to be_falsey
        expect(champ.errors[:value]).to eq(["doit être un nombre entier (sans chiffre après la virgule)"])
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

    context "when max is specified" do
      let(:max) { 10 }
      context 'when the value is equal to max' do
        let(:value) { '10' }

        it { is_expected.to be_truthy }
      end

      context 'when the value is greater than max' do
        let(:value) { 11 }

        it do
          is_expected.to be_falsey
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

        it do
          is_expected.to be_falsey
          expect(champ.errors[:value]).to eq(["doit être supérieur ou égal à 10"])
        end
      end
    end
  end
end
