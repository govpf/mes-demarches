# frozen_string_literal: true

describe TableRowSelector::BaserowAPI do
  before(:all) do
    # Set default Baserow configuration if not present
    unless Rails.application.secrets.baserow&.dig(:url)
      Rails.application.secrets.baserow = {
        url: 'https://api-baserow.mes-demarches.gov.pf',
        token: 'test-token',
        config_table: '631'
      }
    end
  end
  describe '.available_tables' do
    subject { VCR.use_cassette(cassette) { described_class.available_tables } }

    context 'when request is successful' do
      let(:cassette) { 'baserow_api/available_tables_success' }

      it 'returns available tables' do
        tables = subject
        expect(tables).to be_an(Array)
        expect(tables).not_to be_empty
        expect(tables.first).to have_key(:name)
        expect(tables.first).to have_key(:id)
      end
    end
  end

  describe '.search' do
    let(:term) { 'yoga' }
    let(:domain_id) { 7 } # Using domain_id 7 for yoga searches

    context 'when drop_down_other is false' do
      subject { VCR.use_cassette(cassette) { described_class.search(domain_id, term, drop_down_other: false) } }
      let(:cassette) { 'baserow_api/search_yoga_without_other' }

      it 'returns search results without OTHER option' do
        results = subject
        expect(results).to be_an(Array)
        results.each do |result|
          expect(result).to have_key(:label)
          expect(result).to have_key(:value)
          expect(result[:value]).not_to eq('__other__')
        end
      end
    end

    context 'when drop_down_other is true' do
      subject { VCR.use_cassette(cassette) { described_class.search(domain_id, term, drop_down_other: true) } }
      let(:cassette) { 'baserow_api/search_yoga_with_other' }

      it 'returns search results with OTHER option' do
        results = subject
        expect(results).to be_an(Array)

        # Check if OTHER option is present
        other_option = results.find { |result| result[:value] == '__other__' }
        expect(other_option).to be_present
        expect(other_option[:label]).to eq(I18n.t('shared.champs.drop_down_list.other'))
      end
    end

    context 'when drop_down_other is not specified (defaults to false)' do
      subject { VCR.use_cassette(cassette) { described_class.search(domain_id, term) } }
      let(:cassette) { 'baserow_api/search_yoga_default' }

      it 'returns search results without OTHER option' do
        results = subject
        expect(results).to be_an(Array)
        results.each do |result|
          expect(result).to have_key(:label)
          expect(result).to have_key(:value)
          expect(result[:value]).not_to eq('__other__')
        end
      end
    end

    context 'when searching with multiple words using new filters API' do
      let(:multi_word_term) { '1220 chlorure' }
      subject { VCR.use_cassette(cassette) { described_class.search(domain_id, multi_word_term) } }
      let(:cassette) { 'baserow_api/search_multi_word_filters' }

      it 'returns search results using decomposed terms with AND filters' do
        results = subject
        expect(results).to be_an(Array)
        results.each do |result|
          expect(result).to have_key(:label)
          expect(result).to have_key(:value)
        end
      end
    end

    context 'when searching with single word using new filters API' do
      let(:single_word_term) { 'yoga' }
      subject { VCR.use_cassette(cassette) { described_class.search(domain_id, single_word_term) } }
      let(:cassette) { 'baserow_api/search_single_word_filters' }

      it 'returns search results using single filter' do
        results = subject
        expect(results).to be_an(Array)
        results.each do |result|
          expect(result).to have_key(:label)
          expect(result).to have_key(:value)
        end
      end
    end
  end

  describe '.fetch_row' do
    let(:domain_id) { 7 }
    let(:row_id) { 1 } # Using first row from search results

    context 'when row_id is valid' do
      subject { VCR.use_cassette(cassette) { described_class.fetch_row(domain_id, row_id) } }
      let(:cassette) { 'baserow_api/fetch_row_success' }

      it 'returns formatted row data' do
        result = subject
        expect(result).to be_a(Hash)
        expect(result).to have_key(:usager_fields)
        expect(result).to have_key(:instructeur_fields)
        expect(result).to have_key(:row)
        expect(result[:usager_fields]).to be_an(Array)
        expect(result[:instructeur_fields]).to be_an(Array)
        expect(result[:row]).to be_a(Hash)
      end
    end

    context 'when row_id is 0' do
      it 'returns empty hash without making API call' do
        result = described_class.fetch_row(domain_id, 0)
        expect(result).to eq({})
      end
    end

    context 'when row_id is negative' do
      it 'returns empty hash without making API call' do
        result = described_class.fetch_row(domain_id, -1)
        expect(result).to eq({})
      end
    end
  end

  describe '.config' do
    let(:domain_id) { 7 }

    context 'when request is successful' do
      subject { VCR.use_cassette(cassette) { described_class.config(domain_id) } }
      let(:cassette) { 'baserow_api/config_success' }

      it 'returns configuration' do
        result = subject
        expect(result).to be_a(Hash)
        expect(result).to have_key('Table')
        expect(result).to have_key('Champ de recherche')
        expect(result).to have_key('Token')
      end
    end
  end
end
