# frozen_string_literal: true

describe Champs::SiretChamp do
  let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :siret }]) }
  let(:dossier) { create(:dossier, procedure:) }
  let(:champ) { dossier.champs.first.tap { _1.update(value:, etablissement:) } }
  let(:value) { "" }
  let(:etablissement) { nil }

  def with_value(value)
    champ.tap do
      _1.value = value
    end
  end

  describe '#validate' do
    subject { champ.tap { _1.validate(:champs_public_value) } }

    context 'when empty' do
      let(:value) { nil }

      it { is_expected.to be_valid }
    end

    context 'with invalid format - too short for both systems' do
      before { with_value('12345') }

      it { expect(subject.errors[:value]).to include('doit avoir 9 chiffres. Sélectionnez un établissement.') }
    end

    context 'with invalid checksum for 14-char SIRET' do
      before { with_value('12345678901234') }

      it { subject.errors[:value].should include("comporte une erreur de saisie. Corrigez-la.") }
    end

    context 'with valid 14-char format but no etablissement' do
      before { with_value('12345678901245') }

      it { subject.errors[:value].should include("ne correspond pas à un établissement existant") }
    end

    # pf: Add test for 9-char Tahiti number validation
    context 'with valid 9-char Tahiti format but no etablissement' do
      before { with_value('123456789') }

      it { subject.errors[:value].should include("ne correspond pas à un établissement existant") }
    end

    context 'with valid 14-char SIRET and etablissement' do
      before do
        with_value('12345678901245')
        champ.etablissement = build(:etablissement, siret: champ.value)
      end

      it { expect(subject).to be_valid }
    end

    context 'with valid 9-char Tahiti and etablissement' do
      before do
        with_value('123456789')
        champ.etablissement = build(:etablissement, siret: champ.value)
      end

      it { expect(subject).to be_valid }
    end
  end
end
