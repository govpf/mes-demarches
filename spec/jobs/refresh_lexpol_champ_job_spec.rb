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
      it 'refreshes Lexpol data with first instructeur' do
        allow_any_instance_of(APILexpol).to receive(:get_dossier_infos).and_return({
          'statut_libelle' => 'Enregistré par le BC',
          'lienDossier' => 'https://lexpol.cloud.pf/dossier/TEST123456',
          'elements' => [
            { 'typeElement' => 'Arrêté', 'lienLexpol' => 'https://lexpol.cloud.pf/jopf/2025/001' },
          ],
        })

        expect {
          described_class.perform_now(lexpol_champ.id)
          lexpol_champ.reload
        }.to change { lexpol_champ.lexpol_status }.to('Enregistré par le BC')
          .and change { lexpol_champ.lexpol_arrete_lien }.to('https://lexpol.cloud.pf/jopf/2025/001')
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

    context 'when unexpected error occurs' do
      it 'captures the exception without raising' do
        allow_any_instance_of(APILexpol).to receive(:get_dossier_infos).and_raise(StandardError.new('API error'))

        expect(Sentry).to receive(:capture_exception)
        expect { described_class.perform_now(lexpol_champ.id) }.not_to raise_error
      end
    end
  end
end
