describe Champs::NumeroDnChamp do
  let!(:dn) { '2106223' }
  let!(:ddn) { '28/11/1983' }
  let!(:iso_ddn) { '1983-11-28' }
  let(:champ) { build(:champ_numero_dn, numero_dn: dn, date_de_naissance: ddn) }
  let(:external_id) { nil }
  let(:stub_auth) { stub_request(:post, API_CPS_AUTH).to_return(body: { access_token: 'xxx', expires_in: 3600 }.to_json, status: 200) }
  let(:stub) { stub_request(:post, url).to_return(body:, status:) }
  let(:url) { APICps::API.new.send(:url, "covid/assures/coherenceDnDdn/multiples") }
  let(:body) { Rails.root.join('spec', 'fixtures', 'files', 'api_cps', "numero_dn_#{response_type}.json").read }
  let(:status) { 200 }
  let(:response_type) { 'yes' }

  describe 'fetch_external_data' do
    subject { stub_auth; stub; champ.fetch_external_data }

    context 'success (yes)' do
      it {
  expect(subject.value!).to eq({ numero_dn_success: true })
}
    end

    context 'success (no)' do
      let(:response_type) { 'no' }
      it {
  expect(subject.value!).to eq({ numero_dn_success: false })
}
    end

    context 'success (unknow)' do
      let(:response_type) { 'unknown' }
      it {
  expect(subject.value!).to eq({ numero_dn_success: false })
}
    end
  end

  describe '#to_s' do
    let(:champ) { build(:champ_numero_dn, numero_dn:, date_de_naissance:, numero_dn_success:) }
    let(:numero_dn) { nil }
    let(:date_de_naissance) { nil }
    let(:numero_dn_success) { nil }

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
      let(:numero_dn_success) { true }

      it { is_expected.to eq("#{dn} né(e) le #{I18n.l(date_de_naissance.to_date, format: '%d %B %Y')}") }
    end
  end

  describe 'for_export' do
    subject { champ.for_export }

    context 'with no value' do
      let(:champ) { build(:champ_numero_dn, numero_dn: nil, date_de_naissance: nil, numero_dn_success: nil) }

      it { is_expected.to be_nil }
    end

    context 'with dn value' do
      let(:champ) { build(:champ_numero_dn, numero_dn: dn, date_de_naissance: nil, numero_dn_success: nil) }

      it { is_expected.to be_nil }
    end

    context 'with dn & ddn values' do
      let(:champ) { build(:champ_numero_dn, numero_dn: dn, date_de_naissance: ddn) }

      it { is_expected.to eq(dn) }
    end
  end
end
