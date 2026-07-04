# frozen_string_literal: true

RSpec.describe APICps::API do
  subject(:api) { described_class.new }

  describe '#verify' do
    let(:dn) { '1234567' }
    let(:ddn) { '1990-01-01' }
    let(:formatted_ddn) { '01/01/1990' }

    before do
      allow(api).to receive(:access_token).and_return('fake-token')
      allow(Typhoeus).to receive(:post).and_return(response)
    end

    context "quand l'API CPS échoue (indisponibilité / timeout)" do
      let(:response) do
        instance_double(
          Typhoeus::Response,
          success?: false,
          code: 502,
          body: 'Bad Gateway',
          effective_url: 'https://cps.example/covid/assures/coherenceDnDdn/multiples',
          return_message: 'OK',
          total_time: 0.1,
          connect_time: 0.05,
          headers: {}
        )
      end

      # pf: sécurité (F5) — le numéro DN (= identifiant sécurité sociale) et la date de
      # naissance ne doivent JAMAIS apparaître en clair dans les logs serveur.
      it "logge l'erreur sans le numéro DN ni la date de naissance" do
        expect(Rails.logger).to receive(:error) do |message|
          expect(message).not_to include(dn)
          expect(message).not_to include(formatted_ddn)
        end

        expect { api.verify(dn => ddn) }.to raise_error(APIEntreprise::API::Error::RequestFailed)
      end
    end
  end
end
