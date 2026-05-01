# frozen_string_literal: true

RSpec.describe Referentiels::BaserowService, type: :service do
  include Dry::Monads[:result]

  let(:referentiel) { create(:baserow_referentiel) }
  let(:service) { described_class.new(referentiel:) }

  describe '#call' do
    # pf: external_id au format "domain_id:row_id" (cf. BaserowAPI#parse_search_results) —
    # le mode autocomplete/exact_match ne change pas le lookup, c'est le format qui détermine
    context 'with a well-formed external_id "domain:row"' do
      let(:external_id) { '24:123' }

      context 'when API returns valid data' do
        let(:api_response) { { 'Nom' => 'Papeete', 'Archipel' => 'Îles du Vent' } }

        before do
          allow(ReferentielDePolynesie::API).to receive(:fetch_row)
            .with(external_id)
            .and_return(api_response)
        end

        it 'returns a Success with the flat data' do
          result = service.call(external_id)

          expect(result).to be_success
          expect(result.value!).to eq(api_response)
        end
      end

      context 'when API returns nil' do
        before do
          allow(ReferentielDePolynesie::API).to receive(:fetch_row)
            .with(external_id)
            .and_return(nil)
        end

        it 'returns a Failure with code 404' do
          result = service.call(external_id)

          expect(result).to be_failure
          expect(result.failure).to include(retryable: false, code: 404)
        end
      end

      context 'when API returns empty hash' do
        before do
          allow(ReferentielDePolynesie::API).to receive(:fetch_row)
            .with(external_id)
            .and_return({})
        end

        it 'returns a Failure with code 404' do
          result = service.call(external_id)

          expect(result).to be_failure
          expect(result.failure).to include(retryable: false, code: 404)
        end
      end

      context 'when API raises an exception' do
        before do
          allow(ReferentielDePolynesie::API).to receive(:fetch_row)
            .with(external_id)
            .and_raise(StandardError, 'Connection timeout')
        end

        it 'returns a Failure with code 500' do
          result = service.call(external_id)

          expect(result).to be_failure
          expect(result.failure).to include(retryable: false, code: 500)
          expect(result.failure[:reason]).to be_a(StandardError)
        end

        it 'logs the error' do
          expect(Rails.logger).to receive(:error).with(/BaserowService error.*Connection timeout/)
          service.call(external_id)
        end
      end
    end

    context 'with a malformed external_id (saisie libre, anomalie)' do
      it 'returns a Failure with code 400 without calling the API' do
        expect(ReferentielDePolynesie::API).not_to receive(:fetch_row)
        expect(ReferentielDePolynesie::API).not_to receive(:find_by_exact_value)

        result = service.call('not-a-row-id')

        expect(result).to be_failure
        expect(result.failure).to include(retryable: false, code: 400)
      end
    end
  end

  describe '#validate_referentiel' do
    context 'when baserow_config is present and table has data' do
      let(:config) do
        {
          'Table' => '873',
          'Token' => 'test-token',
          'Champs usager' => 'Nom',
          'Champs instructeur' => 'Code',
        }
      end
      let(:sample_row) { { 'id' => 1, 'Nom' => 'Test Row', 'Adresse' => '123 Test St' } }
      let(:api_response) do
        instance_double(Typhoeus::Response, success?: true, body: { 'results' => [sample_row] }.to_json)
      end

      before do
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:config)
          .with(referentiel.table_id)
          .and_return(config)
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:secrets)
          .and_return({ url: 'https://api-baserow.test' })
        allow(Typhoeus).to receive(:get).and_return(api_response)
      end

      it 'returns true' do
        expect(service.validate_referentiel).to be true
      end

      it 'updates last_response with status 200 and flat sample row' do
        service.validate_referentiel
        referentiel.reload

        expect(referentiel.last_response['status']).to eq(200)
        expect(referentiel.last_response['body']).to eq(sample_row)
      end
    end

    context 'when baserow_config is present but table is empty' do
      let(:config) do
        {
          'Table' => '873',
          'Token' => 'test-token',
          'Champs usager' => 'Nom',
          'Champs instructeur' => 'Code',
        }
      end
      let(:api_response) do
        instance_double(Typhoeus::Response, success?: true, body: { 'results' => [] }.to_json)
      end

      before do
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:config)
          .with(referentiel.table_id)
          .and_return(config)
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:secrets)
          .and_return({ url: 'https://api-baserow.test' })
        allow(Typhoeus).to receive(:get).and_return(api_response)
      end

      it 'returns false' do
        expect(service.validate_referentiel).to be false
      end

      it 'updates last_response with status 404' do
        service.validate_referentiel
        referentiel.reload

        expect(referentiel.last_response['status']).to eq(404)
        expect(referentiel.last_response['body']).to include('error' => 'No data in table')
      end
    end

    context 'when baserow_config is nil' do
      before do
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:config)
          .with(referentiel.table_id)
          .and_return(nil)
      end

      it 'returns false' do
        expect(service.validate_referentiel).to be false
      end

      it 'updates last_response with status 404' do
        service.validate_referentiel
        referentiel.reload

        expect(referentiel.last_response['status']).to eq(404)
        expect(referentiel.last_response['body']).to include('error' => 'Config not found')
      end
    end

    context 'when an exception is raised' do
      before do
        allow(ReferentielDePolynesie::BaserowAPI).to receive(:config)
          .and_raise(StandardError, 'API Error')
      end

      it 'returns false' do
        expect(service.validate_referentiel).to be false
      end

      it 'updates last_response with status 500' do
        service.validate_referentiel
        referentiel.reload

        expect(referentiel.last_response['status']).to eq(500)
        expect(referentiel.last_response['body']).to include('error' => 'API Error')
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/BaserowService validation error.*API Error/)
        service.validate_referentiel
      end
    end
  end
end
