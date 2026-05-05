# frozen_string_literal: true

describe Champs::SiretChamp do
  let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :siret }]) }
  let(:dossier) { create(:dossier, procedure:) }
  let(:champ) { dossier.champs.first.tap { _1.update(external_id:, etablissement:) } }
  let(:external_id) { "" }
  let(:etablissement) { nil }

  describe '#validate' do
    subject { champ.tap { _1.validate(:champs_public_value) } }

    context 'when empty' do
      let(:external_id) { nil }

      it { is_expected.to be_valid }
    end

    # pf: invalid format (too short for both SIRET and Tahiti)
    context 'with invalid format - too short for both systems' do
      let(:external_id) { "12345" }

      it { expect(subject.errors[:external_id]).to include('doit comporter 9 chiffres (Tahiti) ou 14 chiffres (SIRET)') }
    end

    context 'with invalid checksum for 14-char SIRET' do
      let(:external_id) { "12345678901234" }

      it { expect(subject.errors[:external_id]).to include("comporte une erreur de saisie. Corrigez-la.") }
    end

    context 'with valid 14-char format but no etablissement' do
      let(:external_id) { "12345678901245" }

      it { expect(subject.errors[:external_id]).to include("ne correspond pas à un établissement existant") }
    end

    # pf: Tahiti 9-char number without matching etablissement
    context 'with valid 9-char Tahiti format but no etablissement' do
      let(:external_id) { "G33972001" }

      it { expect(subject.errors[:external_id]).to include("ne correspond pas à un établissement existant") }
    end

    context 'with valid 14-char SIRET and etablissement' do
      let(:external_id) { "12345678901245" }
      let(:etablissement) { build(:etablissement, siret: external_id) }

      it { expect(subject).to be_valid }
    end

    # pf: Tahiti 9-char number with etablissement
    context 'with valid 9-char Tahiti and etablissement' do
      let(:external_id) { "G33972001" }
      let(:etablissement) { build(:etablissement, siret: external_id) }

      it { expect(subject).to be_valid }
    end

    # pf: ambiguous partial Tahiti number in multiple_found state
    context 'when multiple_found (ambiguous partial Tahiti)' do
      let(:external_id) { "G33972" }
      before { champ.update_columns(external_state: 'multiple_found') }

      it { expect(subject.errors[:external_id]).to include("correspond à plusieurs établissements. Sélectionnez celui qui vous concerne.") }
    end
  end

  describe '.fetch_external_data' do
    let(:api_etablissement_status) { 200 }
    let(:api_etablissement_body) { File.read('spec/fixtures/files/api_entreprise/etablissements.json') }
    let(:token_expired) { false }
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :siret }]) }
    let(:dossier) { create(:dossier, procedure:) }
    let!(:champ) { dossier.champs.first.tap { _1.update!(etablissement: create(:etablissement), external_id: siret, external_state: 'waiting_for_job') } }

    before do
      stub_request(:get, /https:\/\/entreprise.api.gouv.fr\/v3\/insee\/sirene\/etablissements\/#{siret}/)
        .to_return(status: api_etablissement_status, body: api_etablissement_body)
      stub_request(:get, /https:\/\/entreprise.api.gouv.fr\/v3\/insee\/sirene\/unites_legales\/#{siret[0..8]}/)
        .to_return(body: File.read('spec/fixtures/files/api_entreprise/entreprises.json'), status: 200)
      allow_any_instance_of(APIEntrepriseToken).to receive(:roles)
        .and_return(["attestations_fiscales", "attestations_sociales", "bilans_entreprise_bdf"])
    end

    subject(:fetch_external_data) { champ.fetch_external_data }

    shared_examples 'an error occured' do
      it { expect(fetch_external_data).to be_failure }
    end

    context 'when the API is unavailable due to network error' do
      let(:siret) { '82161143100015' }
      let(:api_etablissement_status) { 503 }

      before { expect(APIEntrepriseService).to receive(:api_insee_up?).and_return(true) }

      it_behaves_like 'an error occured'

      it 'sends the error to Sentry' do
        expect(Sentry).to receive(:capture_exception)
        fetch_external_data
      end
    end

    context 'when the API is unavailable due to an api maintenance or pb' do
      let(:siret) { '82161143100015' }
      let(:api_etablissement_status) { 502 }

      before { expect(APIEntrepriseService).to receive(:api_insee_up?).and_return(false) }

      it { expect { fetch_external_data }.to change { champ.reload.etablissement } }

      it { expect { fetch_external_data }.to change { champ.reload.etablissement.as_degraded_mode? }.to(true) }

      it { expect { fetch_external_data }.to change { Etablissement.count }.by(1) }

      it { expect(fetch_external_data).to be_failure }
    end

    context 'when the SIRET is valid but unknown' do
      let(:siret) { '00000000000000' }
      let(:api_etablissement_status) { 404 }

      it_behaves_like 'an error occured'
    end

    context 'when the SIRET informations are retrieved successfully' do
      let(:siret) { '30613890001294' }
      let(:api_etablissement_status) { 200 }
      let(:api_etablissement_body) { File.read('spec/fixtures/files/api_entreprise/etablissements.json') }

      it { expect { fetch_external_data }.to change { champ.reload.etablissement.siret }.to(siret) }

      it { expect { fetch_external_data }.to change { champ.reload.etablissement.naf }.to("8411Z") }

      it { expect { fetch_external_data }.to change { Etablissement.count }.by(1) }

      it { expect(fetch_external_data).to be_success }

      it "fetches the entreprise raison sociale" do
        fetch_external_data
        expect(champ.reload.etablissement.entreprise_raison_sociale).to eq("DIRECTION INTERMINISTERIELLE DU NUMERIQUE")
      end
    end

    context 'when the partial Tahiti number matches several etablissements', vcr: { cassette_name: 'pf_api_entreprise' } do
      let(:siret) { '075390' }

      it 'returns Success with the multiple_found payload (no etablissement created)' do
        result = fetch_external_data
        expect(result).to be_success
        expect(result.value!).to have_key(:multiple_found)
        expect(result.value![:multiple_found]).to be_an(Array)
        expect(result.value![:multiple_found].size).to be > 1
      end

      it 'transitions the champ to multiple_found and stores the candidates when the job runs' do
        champ.fetch!
        champ.reload
        expect(champ).to be_multiple_found
        candidates = champ.etablissement_candidates
        expect(candidates.size).to be > 1
        expect(candidates.first['entreprise_raison_sociale']).to eq('BANQUE SOCREDO')
      end
    end

    context 'when the partial Tahiti number auto-completes (single match)' do
      let(:siret) { '123456' }
      let(:candidate) do
        {
          num_entreprise: 7,
          siret: siret,
          entreprise_raison_sociale: 'ACME TAHITI',
          entreprise_nom_commercial: 'ACME',
          entreprise_siren: siret,
          localite: 'Papeete',
          code_postal: '98713',
          naf: '1234Z',
          libelle_naf: 'Activité fictive',
        }
      end

      before { allow(APIEntrepriseService).to receive(:list_etablissements).with(siret, procedure.id).and_return([candidate]) }

      it 'returns Success with the etablissement and the full 9-char external_id' do
        result = fetch_external_data
        expect(result).to be_success
        expect(result.value!).to have_key(:etablissement)
        expect(result.value![:etablissement]).to be_a(Etablissement)
        expect(result.value![:external_id]).to eq("#{siret}007")
      end

      it 'reuses the candidate data and does NOT make a second API call' do
        expect(APIEntrepriseService).not_to receive(:create_etablissement)
        champ.fetch!
        champ.reload
        expect(champ).to be_fetched
        expect(champ.external_id).to eq("#{siret}007")
        expect(champ.etablissement).to be_present
        expect(champ.etablissement.entreprise_raison_sociale).to eq('ACME TAHITI')
      end
    end
  end
end
