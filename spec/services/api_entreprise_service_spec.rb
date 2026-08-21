# frozen_string_literal: true

describe APIEntrepriseService do
  shared_examples 'schedule fetch of all etablissement params' do
    [
      APIEntreprise::EntrepriseJob, APIEntreprise::ExtraitKbisJob, APIEntreprise::TvaJob,
      APIEntreprise::AssociationJob, APIEntreprise::ExercicesJob,
      APIEntreprise::EffectifsJob, APIEntreprise::EffectifsAnnuelsJob, APIEntreprise::AttestationSocialeJob,
      APIEntreprise::BilansBdfJob,
    ].each do |job|
      it "should enqueue #{job.class.name}" do
        expect { subject }.to have_enqueued_job(job)
      end
    end
  end

  describe '#create_etablissement' do
    before do
      stub_request(:get, /https:\/\/entreprise.api.gouv.fr\/v3\/insee\/sirene\/etablissements\/#{siret}/)
        .to_return(body: etablissements_body, status: etablissements_status)
      stub_request(:get, /https:\/\/entreprise.api.gouv.fr\/v3\/insee\/sirene\/unites_legales\/#{siret[0..8]}/)
        .to_return(body: entreprises_body, status: entreprises_status)
    end

    let(:siret) { '30613890001294' }
    let(:raison_sociale) { "DIRECTION INTERMINISTERIELLE DU NUMERIQUE" }
    let(:etablissements_status) { 200 }
    let(:etablissements_body) { File.read('spec/fixtures/files/api_entreprise/etablissements.json') }
    let(:entreprises_status) { 200 }
    let(:entreprises_body) { File.read('spec/fixtures/files/api_entreprise/entreprises.json') }
    let(:valid_token) { "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" }
    let(:procedure) { create(:procedure, api_entreprise_token: valid_token) }
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:subject) { APIEntrepriseService.create_etablissement(dossier, siret, procedure.id) }

    before do
      allow_any_instance_of(APIEntrepriseToken).to receive(:roles).and_return([])
      allow_any_instance_of(APIEntrepriseToken).to receive(:expired?).and_return(false)
    end

    context 'when service is up' do
      it 'should fetch etablissement params' do
        expect(subject.siret).to eq(siret)
      end

      it 'should fetch entreprise params' do
        expect(subject.entreprise_raison_sociale).to eq(raison_sociale)
      end

      it_behaves_like 'schedule fetch of all etablissement params'
    end

    context 'when etablissement api down' do
      let(:etablissements_status) { 504 }
      let(:etablissements_body) { '' }

      it 'should raise APIEntreprise::API::Error::RequestFailed' do
        expect { subject }.to raise_error(APIEntreprise::API::Error::RequestFailed)
      end
    end

    context 'when etablissement not found' do
      let(:etablissements_status) { 404 }
      let(:etablissements_body) { '' }

      it 'should return nil' do
        expect(subject).to be_nil
      end
    end
  end

  # pf: le routage passait par des comparaisons de longueur divergentes selon la
  # méthode. Un numéro de 10 à 13 caractères partait en appel API via `> 9`.
  describe '#create_etablissement — routage par nature du numéro' do
    let(:procedure) { create(:procedure, api_entreprise_token: nil) }
    let(:dossier) { create(:dossier, procedure: procedure) }

    subject { APIEntrepriseService.create_etablissement(dossier, siret, nil) }

    context 'with an 11-char number, neither Tahiti nor SIRET' do
      let(:siret) { '12345678901' }

      it 'renvoie nil sans aucun appel réseau' do
        expect(APIEntreprise::EtablissementAdapter).not_to receive(:new)
        expect(APIEntreprise::PfEtablissementAdapter).not_to receive(:new)
        expect(subject).to be_nil
      end
    end

    context 'with a partial Tahiti number' do
      let(:siret) { 'G33972' }

      it 'renvoie nil — la résolution passe par list_etablissements' do
        expect(APIEntreprise::EtablissementAdapter).not_to receive(:new)
        expect(APIEntreprise::PfEtablissementAdapter).not_to receive(:new)
        expect(subject).to be_nil
      end
    end

    # pf: on passe désormais identifiant.valeur (normalisé) aux adapters, plutôt
    # que la chaîne brute reçue en argument. Sans ce verrou, une régression qui
    # repasserait à `siret` brut passerait inaperçue : `Siret#remove_whitespace`
    # ne met pas en majuscules, donc une saisie `g33972-001` enverrait `g33972`
    # (minuscules) à l'ISPF.
    it 'transmet à l’adapter ISPF le numéro normalisé en majuscules' do
      expect(APIEntreprise::PfEtablissementAdapter).to receive(:new)
        .with('G33972001', anything).and_return(double(to_params: {}))
      APIEntrepriseService.create_etablissement(dossier, 'g33972-001', nil)
    end
  end

  describe '#list_etablissements — routage par nature du numéro' do
    subject { APIEntrepriseService.list_etablissements(saisie, nil) }

    context 'with a complete Tahiti number' do
      let(:saisie) { 'G33972001' }

      it 'renvoie nil — un numéro complet se résout directement' do
        expect(subject).to be_nil
      end
    end

    context 'with an 11-char number' do
      let(:saisie) { '12345678901' }

      it 'renvoie nil sans appel réseau' do
        expect(APIEntreprise::PfEtablissementAdapter).not_to receive(:new)
        expect(subject).to be_nil
      end
    end
  end

  describe '#create_etablissement_as_degraded_mode' do
    let(:siret) { '41816609600051' }
    let(:valid_token) { "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" }
    let(:procedure) { create(:procedure, api_entreprise_token: valid_token) }
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:user_id) { 12 }

    subject(:etablissement) { APIEntrepriseService.create_etablissement_as_degraded_mode(dossier, siret, user_id) }

    it 'should create an etablissement with minimumal attributes' do
      etablissement = subject

      expect(etablissement.siret).to eq(siret)
      expect(etablissement).to be_as_degraded_mode
    end

    it_behaves_like 'schedule fetch of all etablissement params'

    # pf: sans jeton API Entreprise (cas Polynésie), les jobs de fetch lèveraient
    # tous TokenError et mourraient dans Sidekiq — ils ne doivent pas être lancés.
    context 'without any API Entreprise token (PF)' do
      # la factory :procedure pose un jeton par défaut — on reproduit le cas PF réel (aucun jeton)
      let(:procedure) { create(:procedure, api_entreprise_token: nil) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('API_ENTREPRISE_KEY').and_return(nil)
      end

      it 'still creates the etablissement in degraded mode' do
        expect(subject).to be_as_degraded_mode
      end

      it 'does not enqueue any doomed fetch job' do
        subject
        api_entreprise_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs
          .filter { |job| job[:job].name.start_with?('APIEntreprise::') }
        expect(api_entreprise_jobs).to be_empty
      end
    end
  end

  # pf: une fois API_ENTREPRISE_KEY posé en production, le garde « jeton présent ? »
  # tombe pour toutes les démarches — y compris celles dont les établissements
  # viennent de l'ISPF. Le garde doit porter sur la nature du numéro.
  describe '#perform_later_fetch_jobs — garde par nature du numéro' do
    let(:valid_token) { "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" }
    let(:procedure) { create(:procedure, api_entreprise_token: valid_token) }
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:etablissement) { create(:etablissement, dossier: dossier, siret: siret) }

    subject { APIEntrepriseService.perform_later_fetch_jobs(etablissement, procedure.id, nil) }

    before do
      allow_any_instance_of(APIEntrepriseToken).to receive(:roles).and_return([])
      allow_any_instance_of(APIEntrepriseToken).to receive(:expired?).and_return(false)
    end

    def jobs_enfiles
      ActiveJob::Base.queue_adapter.enqueued_jobs
        .map { |job| job[:job] }
        .filter { |klass| klass.name.start_with?('APIEntreprise::') }
    end

    context 'with a Tahiti etablissement' do
      let(:siret) { 'G33972001' }

      it 'n’enfile aucun job français' do
        subject
        expect(jobs_enfiles).to be_empty
      end
    end

    context 'with a French SIRET etablissement' do
      let(:siret) { '41816609600051' }

      it 'enfile tous les jobs français' do
        subject
        # pf: liste en dur plutôt que la constante testée — sinon retirer un job
        # de FRENCH_ONLY_JOBS laisse ce test vert (garde auto-référentielle).
        expect(jobs_enfiles).to match_array([
          APIEntreprise::EntrepriseJob, APIEntreprise::ExtraitKbisJob, APIEntreprise::TvaJob,
          APIEntreprise::AssociationJob, APIEntreprise::ExercicesJob,
          APIEntreprise::EffectifsJob, APIEntreprise::EffectifsAnnuelsJob,
          APIEntreprise::AttestationSocialeJob, APIEntreprise::BilansBdfJob,
          APIEntreprise::AttestationFiscaleJob,
        ])
      end
    end

    context 'with a Tahiti etablissement in degraded mode' do
      let(:siret) { 'G33972001' }
      let(:etablissement) { create(:etablissement, dossier: dossier, siret: siret, adresse: nil) }

      it 'n’enfile que EtablissementJob, qui sait router les deux sources' do
        subject
        expect(jobs_enfiles).to eq([APIEntreprise::EtablissementJob])
      end
    end

    context 'without any token' do
      let(:siret) { '41816609600051' }
      let(:procedure) { create(:procedure, api_entreprise_token: nil) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('API_ENTREPRISE_KEY').and_return(nil)
      end

      it 'n’enfile rien, même pour un SIRET' do
        subject
        expect(jobs_enfiles).to be_empty
      end
    end
  end

  describe "#api_insee_up?" do
    subject { described_class.fr_api_insee_up? }
    let(:body) { Rails.root.join('spec/fixtures/files/api_entreprise/ping.json').read }
    let(:status) { 200 }

    before do
      stub_request(:get, "https://entreprise.api.gouv.fr/ping/insee/sirene")
        .to_return(body: body, status: status)
    end

    it "returns true when api etablissement is up" do
      expect(subject).to be_truthy
    end

    context "when api entreprise is down" do
      let(:body) { Rails.root.join('spec/fixtures/files/api_entreprise/ping.json').read.gsub('ok', 'HASISSUES') }

      it "returns false" do
        expect(subject).to be_falsey
      end
    end

    context "when api entreprise status is unknown" do
      let(:body) { "" }
      let(:status) { 0 }

      it "returns nil" do
        expect(subject).to be_falsey
      end
    end
  end

  describe "#api_insee_up? for pf" do
    subject { described_class.api_insee_up? }

    let(:body) { File.read('spec/fixtures/files/api_entreprise/i-taiete_status.xml') }
    let(:status) { 200 }

    context "when api entreprise is up" do
      before do
        stub_request(:get, API_ISPF_URL).to_return(body: body, status: status)
      end

      it "returns true" do
        expect(subject).to be_truthy
      end
    end

    context "when api entreprise is down" do
      before do
        stub_request(:get, API_ISPF_URL).to_timeout
      end

      it "returns false" do
        expect(subject).to be_falsy
      end
    end
  end

  # pf: deux fournisseurs, donc deux sondes de santé. Diagnostiquer un échec
  # SIRET avec la santé d'i-taiete (ou l'inverse) fait basculer des dossiers en
  # mode dégradé à tort.
  describe '#service_unavailable_error? — routage des sondes' do
    let(:error) { double('error', network_error?: true, is_a?: false) }

    before do
      stub_request(:get, "https://entreprise.api.gouv.fr/ping/insee/sirene")
        .to_return(body: Rails.root.join('spec/fixtures/files/api_entreprise/ping.json').read, status: 200)
      stub_request(:get, API_ISPF_URL).to_return(status: 200)
    end

    context 'with a French SIRET' do
      let(:identifiant) { IdentifiantEntreprise.parse('41816609600051') }

      it 'interroge la sonde API Entreprise et non celle de l’ISPF' do
        expect(described_class).to receive(:fr_api_insee_up?).and_return(false)
        expect(described_class).not_to receive(:api_insee_up?)
        expect(described_class.service_unavailable_error?(error, target: :insee, identifiant:)).to be true
      end
    end

    context 'with a Tahiti number' do
      let(:identifiant) { IdentifiantEntreprise.parse('G33972001') }

      it 'interroge la sonde ISPF et non celle d’API Entreprise' do
        expect(described_class).to receive(:api_insee_up?).and_return(false)
        expect(described_class).not_to receive(:fr_api_insee_up?)
        expect(described_class.service_unavailable_error?(error, target: :insee, identifiant:)).to be true
      end
    end

    context 'without identifiant' do
      it 'retombe sur la sonde ISPF, comportement historique' do
        expect(described_class).to receive(:api_insee_up?).and_return(false)
        expect(described_class.service_unavailable_error?(error, target: :insee)).to be true
      end
    end
  end
end
