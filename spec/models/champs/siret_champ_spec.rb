# frozen_string_literal: true

describe Champs::SiretChamp do
  let(:champ) { Champs::SiretChamp.new(value: "", dossier: build(:dossier)) }
  before do
    allow(champ).to receive(:type_de_champ).and_return(build(:type_de_champ_siret))
    allow(champ).to receive(:in_dossier_revision?).and_return(true)
  end

  def with_value(value)
    champ.tap { _1.value = value }
  end

  describe '#validate' do
    subject { champ.tap { _1.validate(:champs_public_value) } }

    context 'when empty' do
      it { expect(with_value(nil)).to be_valid }
    end

    context 'with invalid format - too short for both systems' do
      before { with_value('12345') }

      it { expect(subject.errors[:value]).to include('doit avoir 9 chiffres. Sélectionnez un établissement.') }
    end

    context 'with invalid checksum for 14-char SIRET' do
      before { with_value('12345678901234') }

      it { expect(subject.errors[:value].any? { |msg| msg.include?('n’est pas valide') }).to be true }
    end

    context 'with valid 14-char format but no etablissement' do
      before { with_value('12345678901245') }

      it { expect(subject.errors[:value].join(' ')).to match(/aucun.*établissement.*rattaché/) }
    end

    # pf: Add test for 9-char Tahiti number validation
    context 'with valid 9-char Tahiti format but no etablissement' do
      before { with_value('123456789') }

      it { expect(subject.errors[:value].join(' ')).to match(/aucun.*établissement.*rattaché/) }
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
