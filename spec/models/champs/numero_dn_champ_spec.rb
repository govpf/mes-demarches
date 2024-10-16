describe Champs::NumeroDnChamp do
  let!(:dn) { '2106223' }
  let!(:ddn) { '28/11/1983' }
  let!(:iso_ddn) { '1983-11-28' }

  describe '#pack_value', vcr: { cassette_name: 'numero_dn_check' } do
    let(:champ) { build(:champ_numero_dn, numero_dn: dn, date_de_naissance: ddn) }

    before { champ.save }

    it { expect(champ.value).to eq("[\"#{dn}\",\"#{iso_ddn}\"]") }
  end

  describe '#to_s' do
    let(:champ) { build(:champ_numero_dn, numero_dn:, date_de_naissance:) }
    let(:numero_dn) { nil }
    let(:date_de_naissance) { nil }

    subject { champ.to_s }

    context 'with no value' do
      it { is_expected.to eq('') }
    end

    context 'with dn value' do
      let(:numero_dn) { dn }

      it { is_expected.to eq('') }
    end

    context 'with dn & ddn' do
      let(:numero_dn) { dn }
      let(:date_de_naissance) { ddn }

      it { is_expected.to eq("#{dn} né(e) le #{I18n.l(date_de_naissance.to_date, format: '%d %B %Y')}") }
    end
  end

  describe 'for_export' do
    subject { champ.for_export }

    context 'with no value' do
      let(:champ) { build(:champ_numero_dn, numero_dn: nil, date_de_naissance: nil) }

      it { is_expected.to be_nil }
    end

    context 'with dn value' do
      let(:champ) { build(:champ_numero_dn, numero_dn: dn, date_de_naissance: nil) }

      it { is_expected.to be_nil }
    end

    context 'with dn & ddn values' do
      let(:champ) { build(:champ_numero_dn, numero_dn: dn, date_de_naissance: ddn) }

      it { is_expected.to eq(dn) }
    end
  end
end
