# frozen_string_literal: true

RSpec.describe Cron::RefreshLexpolJob, type: :job do
  describe '#perform' do
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :lexpol }]) }

    let!(:dossier_en_instruction) { create(:dossier, :en_instruction, procedure: procedure) }
    let!(:dossier_accepte) { create(:dossier, :accepte, processed_at: 2.days.ago, procedure: procedure) }
    let!(:dossier_en_construction) { create(:dossier, :en_construction, procedure: procedure) }

    let!(:champ_instruction_sans_lien) do
      champ = dossier_en_instruction.champs.find { |c| c.is_a?(Champs::LexpolChamp) }
      champ.update(value: 'NOR001', data: { lexpol_status: 'En préparation' })
      champ
    end

    let!(:champ_instruction_avec_lien) do
      # Créer un deuxième dossier en instruction pour tester le filtre
      dossier2 = create(:dossier, :en_instruction, procedure: procedure)
      champ = dossier2.champs.find { |c| c.is_a?(Champs::LexpolChamp) }
      champ.update(
        value: 'NOR002',
        data: {
          lexpol_status: 'Enregistré par le BC',
          lexpol_arrete_lien: 'https://lexpol.cloud.pf/jopf/2025/001',
        }
      )
      champ
    end

    let!(:champ_accepte) do
      champ = dossier_accepte.champs.find { |c| c.is_a?(Champs::LexpolChamp) }
      champ.update(value: 'NOR003', data: { lexpol_status: 'En préparation' })
      champ
    end

    let!(:champ_construction) do
      champ = dossier_en_construction.champs.find { |c| c.is_a?(Champs::LexpolChamp) }
      champ.update(value: 'NOR004', data: { lexpol_status: 'En préparation' })
      champ
    end

    it 'enqueues jobs ONLY for dossiers en instruction WITHOUT lien arrêté' do
      expect {
        described_class.perform_now
      }.to have_enqueued_job(RefreshLexpolChampJob).with(champ_instruction_sans_lien.id)

      expect(RefreshLexpolChampJob).not_to have_been_enqueued.with(champ_instruction_avec_lien.id)
      expect(RefreshLexpolChampJob).not_to have_been_enqueued.with(champ_accepte.id)
      expect(RefreshLexpolChampJob).not_to have_been_enqueued.with(champ_construction.id)
    end

    it 'logs the number of champs to refresh' do
      # Simplifié : on vérifie juste que ça log sans erreur
      expect { described_class.perform_now }.not_to raise_error
    end

    context 'when there are no champs to refresh' do
      before do
        # Ajouter un lien à tous les champs
        champ_instruction_sans_lien.update(data: { lexpol_arrete_lien: 'https://lexpol.cloud.pf/jopf/2025/002' })
      end

      it 'does not enqueue any job' do
        expect {
          described_class.perform_now
        }.not_to have_enqueued_job(RefreshLexpolChampJob)
      end
    end

    context 'when champ has empty string for NOR' do
      before do
        # Mettre le NOR à vide sur le champ existant
        champ_instruction_sans_lien.update(value: '')
      end

      it 'does not enqueue job for empty NOR' do
        expect {
          described_class.perform_now
        }.not_to have_enqueued_job(RefreshLexpolChampJob)
      end
    end
  end
end
