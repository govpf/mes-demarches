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
    context 'when empty' do
      subject { with_value(nil).tap { _1.validate(:champs_public_value) } }

      it { is_expected.to be_valid }
    end

    context 'with invalid format (too short)' do
      subject { with_value('12345').tap { _1.validate(:champs_public_value) } }

      it { expect(subject.errors[:value]).to include('doit avoir 9 chiffres. Selectionnez un établissement.') }
    end

    # PF: Test du cas nominal avec numéro TAHITI valide et établissement lié
    context 'with valid SIRET and etablissement' do
      subject { with_value('12345678901245').tap { _1.etablissement = build(:etablissement, siret: _1.value); _1.validate(:champs_public_value) } }

      it { is_expected.to be_valid }
    end
  end
end
