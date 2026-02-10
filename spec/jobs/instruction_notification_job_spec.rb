# frozen_string_literal: true

describe InstructionNotificationJob, type: :job do
  let(:dossier) { create(:dossier, :en_instruction) }

  describe '.schedule_for_dossier' do
    it 'programme le job avec le délai fixe' do
      expect(described_class).to receive(:set)
        .with(wait: 15.minutes)
        .and_return(double(perform_later: true))

      described_class.schedule_for_dossier(dossier)
    end
  end

  describe '#perform' do
    context 'quand le dossier est toujours en instruction' do
      it 'envoie l\'email instruction' do
        expect(NotificationMailer).to receive(:send_en_instruction_notification)
          .with(dossier)
          .and_return(double(deliver_now: true))

        described_class.new.perform(dossier.id)
      end
    end

    context 'quand le dossier est en brouillon' do
      before { dossier.brouillon! }

      it 'n\'envoie pas l\'email instruction' do
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)

        described_class.new.perform(dossier.id)
      end
    end

    context 'quand le dossier est en construction' do
      before { dossier.en_construction! }

      it 'n\'envoie pas l\'email instruction' do
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)

        described_class.new.perform(dossier.id)
      end
    end

    context 'quand le dossier est accepté' do
      before { dossier.update!(state: 'accepte') }

      it 'n\'envoie pas l\'email instruction' do
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)

        described_class.new.perform(dossier.id)
      end
    end

    context 'quand le dossier est refusé' do
      before { dossier.update!(state: 'refuse') }

      it 'n\'envoie pas l\'email instruction' do
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)

        described_class.new.perform(dossier.id)
      end
    end

    context 'quand le dossier est classé sans suite' do
      before { dossier.update!(state: 'sans_suite') }

      it 'n\'envoie pas l\'email instruction' do
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)

        described_class.new.perform(dossier.id)
      end
    end

    context 'quand le dossier est supprimé par l\'usager' do
      before { dossier.update!(hidden_by_user_at: Time.zone.now) }

      it 'n\'envoie pas l\'email instruction' do
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)

        described_class.new.perform(dossier.id)
      end
    end

    context 'quand le dossier n\'existe plus' do
      it 'ne lève pas d\'erreur' do
        expect { described_class.new.perform(999999) }.not_to raise_error
      end

      it 'n\'envoie pas d\'email' do
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)

        described_class.new.perform(999999)
      end
    end
  end
end
