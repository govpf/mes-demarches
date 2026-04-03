# frozen_string_literal: true

describe Champs::SiretChamp do
  let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :siret }]) }
  let(:dossier) { create(:dossier, procedure:) }
  let(:champ) { dossier.champs.first }

  def with_value(value)
    champ.tap do
      _1.value = value
    end
  end

  describe '#validate' do
    subject { champ.tap { _1.validate(:champs_public_value) } }

    context 'when empty' do
      it { is_expected.to be_valid }
    end

    # pf: test for partial Tahiti numbers (too short for both systems)
    context 'with invalid format - too short for both systems' do
      before { with_value('12345') }

      it { expect(subject.errors[:value]).to include('doit avoir 9 chiffres. Sélectionnez un établissement.') }
    end

    context 'with invalid checksum for 14-char SIRET' do
      before { with_value('12345678901234') }

      it { expect(subject.errors[:value]).not_to be_empty }
    end

    context 'with valid 14-char format but no etablissement' do
      before { with_value('12345678901245') }

      it { expect(subject.errors[:value]).to include('ne correspond pas à un établissement existant') }
    end

    # pf: Add test for 9-char Tahiti number validation
    context 'with valid 9-char Tahiti format but no etablissement' do
      before { with_value('123456789') }

      it { expect(subject.errors[:value]).to include('ne correspond pas à un établissement existant') }
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

    # pf: Tahiti hyphen format → cleaned to 9 chars, requires etablissement
    context 'with Tahiti number formatted with hyphen and no etablissement' do
      before { with_value('123456-789') }

      it { expect(subject.errors[:value]).to include('ne correspond pas à un établissement existant') }
    end

    # pf: 6-char partial Tahiti requires selection from list
    context 'with a partial 6-char Tahiti number and no etablissement' do
      before { with_value('123456') }

      it { expect(subject.errors[:value]).to include('doit avoir 9 chiffres. Sélectionnez un établissement.') }
    end

    # pf: 6-char Tahiti with auto-selected etablissement is valid
    context 'with partial 6-char Tahiti and auto-selected etablissement' do
      before do
        with_value('123456')
        champ.etablissement = build(:etablissement, siret: '123456001')
      end

      it { expect(subject).to be_valid }
    end

    # pf: length 10-13 is invalid for both SIRET and Tahiti
    context 'with a 11-char value (invalid length for both systems)' do
      before { with_value('12345678901') }

      it { expect(subject.errors[:value]).not_to be_empty }
    end
  end

  # pf: SiretChamp does NOT override uses_external_data? because PF uses a fully
  # synchronous flow (Champs::SiretController + SiretChampEtablissementFetchableConcern).
  # Overriding it to true would trigger reset_external_data! on every dossier save
  # via users/dossiers_controller, which would wipe value and etablissement_id.
  describe '#uses_external_data?' do
    it 'returns false (PF stays out of upstream state machine)' do
      expect(champ.uses_external_data?).to be false
    end
  end
end
