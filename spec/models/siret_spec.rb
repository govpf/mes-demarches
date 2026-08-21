# frozen_string_literal: true

describe Siret, type: :model do
  subject { Siret.new(siret: siret.dup) } # .dup in order to simulate a non literal user string

  context 'with no siret provided' do
    let(:siret) { '' }

    it { is_expected.to be_invalid }
  end

  context 'with a siret that contains letters' do
    let(:siret) { 'A1B1C6D9E0F0G1' }

    it { is_expected.to be_invalid }
  end

  context 'with a siret that is too short' do
    let(:siret) { '1234567890' }

    it { is_expected.to be_invalid }
  end

  context 'with a siret that is too long' do
    let(:siret) { '12345678901234567890' }

    it { is_expected.to be_invalid }
  end

  context 'with a lunh-invalid siret' do
    let(:siret) { '41816609600052' }

    it { is_expected.to be_invalid }
  end

  context 'with a lunh-invalid La Poste siret' do
    let(:siret) { '35600000018723' }

    it { is_expected.to be_valid }
  end

  context 'with a valid siret' do
    let(:siret) { '41816609600051' }

    it { is_expected.to be_valid }
  end

  # pf: le numéro Tahiti est le format dominant en Polynésie — il n'était
  # couvert par aucun exemple, d'où la divergence historique sur les 7-8 car.
  context 'with a 6-char Tahiti number' do
    let(:siret) { 'G33972' }

    it { is_expected.to be_valid }
  end

  context 'with a 7-char partial Tahiti number' do
    let(:siret) { 'G339720' }

    it { is_expected.to be_valid }
  end

  context 'with an 8-char partial Tahiti number' do
    let(:siret) { 'G3397200' }

    it { is_expected.to be_valid }
  end

  context 'with a 9-char Tahiti number' do
    let(:siret) { 'G33972001' }

    it { is_expected.to be_valid }
  end

  context 'with a 9-char numeric-only Tahiti number' do
    let(:siret) { '002253001' }

    it { is_expected.to be_valid }
  end

  context 'with a hyphen-formatted Tahiti number' do
    let(:siret) { 'G33972-001' }

    it { is_expected.to be_valid }
  end

  context 'with an 11-char number, neither Tahiti nor SIRET' do
    let(:siret) { '12345678901' }

    it { is_expected.to be_invalid }
  end
end
