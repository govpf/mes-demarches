# frozen_string_literal: true

describe InstructionNotificationJob, type: :job do
  let(:dossier) { create(:dossier, :en_instruction) }
  
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
      before { dossier.accepte! }
      
      it 'n\'envoie pas l\'email instruction' do
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier est refusé' do
      before { dossier.refuse! }
      
      it 'n\'envoie pas l\'email instruction' do
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier est classé sans suite' do
      before { dossier.classer_sans_suite! }
      
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