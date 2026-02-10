# frozen_string_literal: true

RSpec.describe Cron::BackfillSiretDegradedModeJob, type: :job do
  let(:job) { described_class.new }

  describe '.perform' do
    let(:new_adresse) { '7 rue du puits, coye la foret' }

    context "backfill réussi pour un établissement lié à un dossier" do
      let(:etablissement) { create(:etablissement, adresse: nil, siret: '01234567891011') }
      let(:dossier) { create(:dossier, :en_construction, etablissement: etablissement) }

      before { dossier }

      it "met à jour l'adresse de l'établissement" do
        allow_any_instance_of(APIEntreprise::EtablissementAdapter).to receive(:to_params).and_return({ adresse: new_adresse })
        expect { described_class.perform_now }.to change { etablissement.reload.adresse }.from(nil).to(new_adresse)
      end
    end

    context "backfill réussi pour un établissement lié à un champ SIRET" do
      let(:etablissement) { create(:etablissement, adresse: nil, siret: '01234567891011') }
      let(:procedure) { create(:procedure, :published, types_de_champ_public:) }
      let(:types_de_champ_public) { [{ type: :siret }] }
      let(:dossier) { create(:dossier, :with_populated_champs, procedure:) }
      let(:champ_siret) { dossier.champs.first }

      before do
        champ_siret.update_column(:etablissement_id, etablissement.id)
      end

      it "met à jour l'adresse de l'établissement" do
        allow_any_instance_of(APIEntreprise::EtablissementAdapter).to receive(:to_params).and_return({ adresse: new_adresse })
        expect { described_class.perform_now }.to change { etablissement.reload.adresse }.from(nil).to(new_adresse)
      end
    end

    context "backfill échoué pour un dossier : demande de correction automatique" do
      let(:instructeur) { create(:instructeur) }
      let(:procedure) { create(:procedure, :published) }
      let(:dossier) { create(:dossier, :en_construction, procedure: procedure, etablissement: etablissement) }
      let(:etablissement) { create(:etablissement, adresse: nil, siret: '123456789') }

      before do
        procedure.defaut_groupe_instructeur.instructeurs << instructeur
        dossier
        allow(APIEntrepriseService).to receive(:update_etablissement_from_degraded_mode).and_return(nil)
      end

      it "crée une correction et un commentaire" do
        expect { described_class.perform_now }
          .to change { DossierCorrection.count }.by(1)
          .and change { Commentaire.count }.by(1)
      end

      it "le commentaire contient le numéro TAHITI" do
        described_class.perform_now
        commentaire = Commentaire.last
        expect(commentaire.body).to include('123456789')
        expect(commentaire.body).to include('TAHITI')
      end

      it "le commentaire est envoyé par un instructeur du groupe" do
        described_class.perform_now
        expect(Commentaire.last.instructeur).to eq(instructeur)
      end

      it "le message contient un lien vers la page établissement" do
        described_class.perform_now
        expect(Commentaire.last.body).to include("/dossiers/#{dossier.id}/etablissement")
      end
    end

    context "backfill échoué via champ SIRET : message avec nom du champ" do
      let(:instructeur) { create(:instructeur) }
      let(:procedure) { create(:procedure, :published, types_de_champ_public: [{ type: :siret }]) }
      let(:dossier) { create(:dossier, :en_construction, :with_populated_champs, procedure: procedure) }
      let(:etablissement) { create(:etablissement, adresse: nil, siret: '1234567') }
      let(:champ_siret) { dossier.champs.first }

      before do
        procedure.defaut_groupe_instructeur.instructeurs << instructeur
        champ_siret.update_column(:etablissement_id, etablissement.id)
        allow(APIEntrepriseService).to receive(:update_etablissement_from_degraded_mode).and_return(nil)
      end

      it "crée une correction avec un message mentionnant le champ et le lien modifier" do
        described_class.perform_now
        commentaire = Commentaire.last
        expect(commentaire.body).to include("corriger le champ")
        expect(commentaire.body).to include("/modifier")
      end
    end

    context "anti-doublon : correction déjà en attente" do
      let(:instructeur) { create(:instructeur) }
      let(:procedure) { create(:procedure, :published) }
      let(:dossier) { create(:dossier, :en_construction, procedure: procedure, etablissement: etablissement) }
      let(:etablissement) { create(:etablissement, adresse: nil, siret: '123456789') }

      before do
        procedure.defaut_groupe_instructeur.instructeurs << instructeur
        existing_commentaire = create(:commentaire, dossier: dossier, instructeur: instructeur)
        dossier.flag_as_pending_correction!(existing_commentaire, :incorrect)
        allow(APIEntrepriseService).to receive(:update_etablissement_from_degraded_mode).and_return(nil)
      end

      it "ne crée pas de nouvelle correction" do
        expect { described_class.perform_now }
          .not_to change { DossierCorrection.count }
      end
    end

    context "pas d'instructeur disponible" do
      let(:procedure) { create(:procedure, :published) }
      let(:dossier) { create(:dossier, :en_construction, procedure: procedure, etablissement: etablissement) }
      let(:etablissement) { create(:etablissement, adresse: nil, siret: '123456789') }

      before do
        procedure.defaut_groupe_instructeur.instructeurs.destroy_all
        dossier
        allow(APIEntrepriseService).to receive(:update_etablissement_from_degraded_mode).and_return(nil)
      end

      it "ne crée pas de correction" do
        expect { described_class.perform_now }
          .not_to change { DossierCorrection.count }
      end
    end

    context "exception pendant le traitement" do
      let(:instructeur) { create(:instructeur) }
      let(:procedure) { create(:procedure, :published) }
      let(:dossier) { create(:dossier, :en_construction, procedure: procedure, etablissement: etablissement) }
      let(:etablissement) { create(:etablissement, adresse: nil, siret: '123456789') }

      before do
        procedure.defaut_groupe_instructeur.instructeurs << instructeur
        dossier
        allow(APIEntrepriseService).to receive(:update_etablissement_from_degraded_mode).and_raise(StandardError, 'API timeout')
        allow(Sentry).to receive(:capture_exception)
      end

      it "capture l'exception dans Sentry sans planter le job" do
        expect { described_class.perform_now }.not_to raise_error
        expect(Sentry).to have_received(:capture_exception).with(
          an_instance_of(StandardError),
          extra: hash_including(:etablissement_id, :dossier_id)
        )
      end
    end
  end

  describe '#detect_error_reason' do
    subject { job.send(:detect_error_reason, siret) }

    context "numéro trop court (0-5 chiffres)" do
      let(:siret) { '12345' }
      it { is_expected.to eq(:too_short) }
    end

    context "numéro vide" do
      let(:siret) { '' }
      it { is_expected.to eq(:too_short) }
    end

    context "numéro ambigu (6-8 chiffres, TAHITI partiel)" do
      let(:siret) { '123456' }
      it { is_expected.to eq(:ambiguous) }
    end

    context "8 chiffres" do
      let(:siret) { '12345678' }
      it { is_expected.to eq(:ambiguous) }
    end

    context "TAHITI valide mais introuvable (9 chiffres)" do
      let(:siret) { '123456789' }
      it { is_expected.to eq(:not_found) }
    end

    context "longueur invalide entre TAHITI et SIRET (10-13 chiffres)" do
      let(:siret) { '1234567890' }
      it { is_expected.to eq(:invalid_length) }
    end

    context "13 chiffres" do
      let(:siret) { '1234567890123' }
      it { is_expected.to eq(:invalid_length) }
    end

    context "SIRET français valide mais introuvable (14 chiffres)" do
      let(:siret) { '12345678901234' }
      it { is_expected.to eq(:not_found) }
    end

    context "plus de 14 chiffres" do
      let(:siret) { '123456789012345' }
      it { is_expected.to eq(:invalid_length) }
    end

    context "avec espaces et tirets (nettoyage)" do
      let(:siret) { '123 456-789' }
      it { is_expected.to eq(:not_found) }
    end
  end

  describe '#error_explanation' do
    subject { job.send(:error_explanation, siret, reason) }
    let(:siret) { '123456789' }

    context ":not_found" do
      let(:reason) { :not_found }
      it { is_expected.to include("pas été trouvé dans le registre") }
    end

    context ":ambiguous" do
      let(:reason) { :ambiguous }
      let(:siret) { '123456' }
      it { is_expected.to include("incomplet") }
      it { is_expected.to include("9 chiffres") }
    end

    context ":too_short" do
      let(:reason) { :too_short }
      let(:siret) { '123' }
      it { is_expected.to include("format attendu") }
    end

    context ":invalid_length" do
      let(:reason) { :invalid_length }
      let(:siret) { '1234567890' }
      it { is_expected.to include("format attendu") }
    end

    context "raison inconnue" do
      let(:reason) { :unknown }
      it { is_expected.to include("pas pu être vérifié") }
    end
  end
end
