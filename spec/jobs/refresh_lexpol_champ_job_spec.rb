# frozen_string_literal: true

RSpec.describe RefreshLexpolChampJob, type: :job do
  let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :lexpol }]) }
  let(:dossier) { create(:dossier, :en_instruction, procedure: procedure) }
  let(:instructeur1) { create(:instructeur, email: 'instructeur1@example.com') }
  let(:instructeur2) { create(:instructeur, email: 'instructeur2@example.com') }
  let(:lexpol_champ) do
    champ = dossier.champs.find { |c| c.is_a?(Champs::LexpolChamp) }
    champ.update(value: 'TEST123456', data: { lexpol_status: 'En préparation' })
    champ
  end

  before do
    instructeur1.follow(dossier)
    instructeur2.follow(dossier)
  end

  describe '#perform' do
    context 'when champ has no NOR' do
      it 'skips the refresh' do
        lexpol_champ.update(value: nil)

        expect_any_instance_of(LexpolService).not_to receive(:refresh_lexpol_data!)
        described_class.perform_now(lexpol_champ.id)
      end
    end

    context 'when champ already has lexpol_arrete_lien' do
      it 'skips the refresh' do
        lexpol_champ.update(data: { lexpol_arrete_lien: 'https://lexpol.cloud.pf/jopf/2025/001' })

        expect_any_instance_of(LexpolService).not_to receive(:refresh_lexpol_data!)
        described_class.perform_now(lexpol_champ.id)
      end
    end

    context 'when first instructeur has access' do
      it 'refreshes Lexpol data with first instructeur (Arrêté en CM)' do
        allow_any_instance_of(APILexpol).to receive(:get_dossier_infos).and_return({
          'statut_libelle' => 'Enregistré par le BC',
          'lienDossier' => 'https://lexpol.cloud.pf/dossier/TEST123456',
          'elements' => [
            { 'typeElement' => 'Rapport de présentation en CM', 'lienLexpol' => nil },
            { 'typeElement' => 'Arrêté en CM', 'lienLexpol' => 'http://lexpol.cloud.pf/LexpolAfficheTexte.php?ge&texte=1038589' },
            { 'typeElement' => 'Note de présentation', 'lienLexpol' => nil },
          ],
        })

        expect {
          described_class.perform_now(lexpol_champ.id)
          lexpol_champ.reload
        }.to change { lexpol_champ.lexpol_status }.to('Enregistré par le BC')
          .and change { lexpol_champ.lexpol_arrete_lien }.to('http://lexpol.cloud.pf/LexpolAfficheTexte.php?ge&texte=1038589')
      end

      it 'matches "Arrêté en PR" too' do
        allow_any_instance_of(APILexpol).to receive(:get_dossier_infos).and_return({
          'statut_libelle' => 'Publié au JOPF',
          'elements' => [
            { 'typeElement' => 'Arrêté en PR', 'lienLexpol' => 'http://lexpol.cloud.pf/LexpolAfficheTexte.php?texte=999' },
          ],
        })

        described_class.perform_now(lexpol_champ.id)
        expect(lexpol_champ.reload.lexpol_arrete_lien).to eq('http://lexpol.cloud.pf/LexpolAfficheTexte.php?texte=999')
      end

      it 'ne remonte pas les éléments non-arrêtés (rapport, note, souche)' do
        allow_any_instance_of(APILexpol).to receive(:get_dossier_infos).and_return({
          'statut_libelle' => 'Enregistré par le BC',
          'elements' => [
            { 'typeElement' => 'Rapport de présentation en CM', 'lienLexpol' => 'http://example/rapport' },
            { 'typeElement' => 'Souche(s)', 'lienLexpol' => nil },
            { 'typeElement' => 'Note de présentation', 'lienLexpol' => 'http://example/note' },
          ],
        })

        described_class.perform_now(lexpol_champ.id)
        expect(lexpol_champ.reload.lexpol_arrete_lien).to be_nil
      end
    end

    context 'when first instructeur is denied but second has access' do
      it 'falls back to second instructeur' do
        call_count = 0
        allow_any_instance_of(APILexpol).to receive(:get_dossier_infos) do
          call_count += 1
          if call_count == 1
            raise APILexpol::LexpolAccessDenied.new('instructeur1@example.com', 403)
          else
            {
              'statut_libelle' => 'Soumis au Directeur',
              'lienDossier' => 'https://lexpol.cloud.pf/dossier/TEST123456',
              'elements' => [],
            }
          end
        end

        expect {
          described_class.perform_now(lexpol_champ.id)
          lexpol_champ.reload
        }.to change { lexpol_champ.lexpol_status }.to('Soumis au Directeur')

        expect(call_count).to eq(2) # Tried with both instructeurs
      end
    end

    # pf: Lexpol : un dossier « En préparation » n'est visible que de son rédacteur
    context 'ordre des comptes personnels' do
      let(:infos) { { 'statut_libelle' => 'En préparation', 'elements' => [] } }
      let(:comptes_essayes) { [] }
      let(:comptes_autorises) { [] }

      before do
        allow_any_instance_of(APILexpol).to receive(:get_dossier_infos) do |api|
          comptes_essayes << api.email_agent
          raise APILexpol::LexpolAccessDenied.new(api.email_agent, 403) unless comptes_autorises.include?(api.email_agent)
          infos
        end
      end

      context 'quand l’auteur est enregistré sur le champ' do
        let(:comptes_autorises) { ['redactrice@drm.gov.pf'] }

        before { lexpol_champ.update!(lexpol_auteur_email: 'redactrice@drm.gov.pf') }

        it 'essaie l’auteur en premier, en un seul appel' do
          described_class.perform_now(lexpol_champ.id)

          expect(comptes_essayes).to eq(['redactrice@drm.gov.pf'])
          expect(lexpol_champ.reload.lexpol_status).to eq('En préparation')
        end
      end

      context 'quand l’auteur n’est pas enregistré (champ antérieur)' do
        let(:comptes_autorises) { ['redactrice@drm.gov.pf'] }

        before { lexpol_champ.update_column(:updated_by, 'redactrice@drm.gov.pf') }

        it 'se replie sur le dernier agent ayant créé ou mis à jour le champ' do
          described_class.perform_now(lexpol_champ.id)

          expect(comptes_essayes).to eq(['redactrice@drm.gov.pf'])
        end
      end

      # pf: l'auteur connu couvre le cas « En préparation » : inutile de balayer tout le groupe
      context 'quand ni l’auteur ni les suiveurs n’y ont accès' do
        let(:collegue) { create(:instructeur, email: 'collegue@drm.gov.pf') }
        let(:comptes_autorises) { ['collegue@drm.gov.pf'] }

        before do
          dossier.groupe_instructeur.add(collegue)
          lexpol_champ.update!(lexpol_auteur_email: 'redactrice@drm.gov.pf')
        end

        it 'n’essaie pas les autres instructeurs du groupe' do
          described_class.perform_now(lexpol_champ.id)

          expect(comptes_essayes.first).to eq('redactrice@drm.gov.pf')
          expect(comptes_essayes).to match_array(['redactrice@drm.gov.pf', 'instructeur1@example.com', 'instructeur2@example.com'])
          expect(comptes_essayes).not_to include('collegue@drm.gov.pf')
        end
      end

      context 'quand un compte n’est pas habilité dans Lexpol (401)', :caching do
        let(:comptes_autorises) { ['instructeur2@example.com'] }

        before do
          allow_any_instance_of(APILexpol).to receive(:get_dossier_infos) do |api|
            comptes_essayes << api.email_agent
            raise APILexpol::LexpolAccessDenied.new(api.email_agent, 401) if api.email_agent == 'instructeur1@example.com'
            infos
          end
        end

        it 'ne retente pas ce compte sur les champs suivants du lot' do
          described_class.perform_now(lexpol_champ.id)
          described_class.perform_now(lexpol_champ.id)

          expect(comptes_essayes.count('instructeur1@example.com')).to eq(1)
        end
      end
    end

    # pf: le compte de service est celui du numéro Tahiti du SERVICE de la démarche,
    # pas celui de l'entreprise du demandeur
    context 'avec un compte de service configuré pour le service de la démarche' do
      let(:procedure) { create(:procedure, :published, :with_service, types_de_champ_public: [{ type: :lexpol }]) }
      let(:infos) { { 'statut_libelle' => 'Soumis au Directeur', 'elements' => [] } }
      let(:comptes_utilises) { [] }

      before do
        procedure.service.update_column(:siret, '003970')
        allow(APILexpol).to receive(:service_emails).and_return({ '003970' => 'redacteur.geda@service.gov.pf' })
        allow(APILexpol).to receive(:new).and_wrap_original do |original, *args|
          original.call(*args).tap { |api| comptes_utilises << api.instance_variable_get(:@email_agent) }
        end
      end

      context 'quand aucun instructeur n’a accès' do
        before do
          allow_any_instance_of(APILexpol).to receive(:get_dossier_infos) do |api|
            raise APILexpol::LexpolAccessDenied.new(api.instance_variable_get(:@email_agent), 403) unless api.using_service_account?
            infos
          end
        end

        it 'se replie sur le compte de service du numéro Tahiti du service' do
          described_class.perform_now(lexpol_champ.id)

          expect(lexpol_champ.reload.lexpol_status).to eq('Soumis au Directeur')
          expect(comptes_utilises.last).to eq('redacteur.geda@service.gov.pf')
        end
      end

      context 'pour un dossier de test (révision brouillon)' do
        let(:dossier) { create(:dossier, :en_instruction, procedure: procedure, revision: procedure.draft_revision) }

        before { allow_any_instance_of(APILexpol).to receive(:get_dossier_infos).and_return(infos) }

        it 'interroge d’abord le compte de service, qui a créé le dossier Lexpol' do
          expect(dossier.revision).to be_draft
          described_class.perform_now(lexpol_champ.id)

          expect(comptes_utilises).to eq(['redacteur.geda@service.gov.pf'])
          expect(lexpol_champ.reload.lexpol_status).to eq('Soumis au Directeur')
        end
      end

      context 'pour un dossier réel' do
        before { allow_any_instance_of(APILexpol).to receive(:get_dossier_infos).and_return(infos) }

        it 'interroge d’abord les instructeurs' do
          expect(dossier.revision).not_to be_draft
          described_class.perform_now(lexpol_champ.id)

          expect(comptes_utilises.first).to eq(dossier.followers_instructeurs.first.email)
        end
      end
    end

    context 'when Lexpol is unavailable (timeout, 5xx)' do
      before do
        allow_any_instance_of(APILexpol).to receive(:get_dossier_infos)
          .and_raise(APILexpol::LexpolUnavailable.new("L'authentification Lexpol", 0, :operation_timedout))
      end

      it 'reschedules the job instead of giving up until the next day' do
        expect(Sentry).not_to receive(:capture_exception)

        expect { described_class.perform_now(lexpol_champ.id) }
          .to have_enqueued_job(described_class).with(lexpol_champ.id)
      end

      it 'reports to Sentry once retries are exhausted' do
        job = described_class.new(lexpol_champ.id)
        job.exception_executions = { '[APILexpol::LexpolUnavailable]' => 4 }

        expect(Sentry).to receive(:capture_exception).with(APILexpol::LexpolUnavailable, extra: { champ_id: lexpol_champ.id })
        expect { job.perform_now }.not_to have_enqueued_job(described_class)
      end
    end

    context 'when unexpected error occurs' do
      it 'captures the exception without raising' do
        allow_any_instance_of(APILexpol).to receive(:get_dossier_infos).and_raise(StandardError.new('API error'))

        expect(Sentry).to receive(:capture_exception)
        expect { described_class.perform_now(lexpol_champ.id) }.not_to raise_error
      end
    end
  end
end
