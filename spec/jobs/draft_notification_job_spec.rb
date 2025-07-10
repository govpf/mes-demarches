# frozen_string_literal: true

describe DraftNotificationJob, type: :job do
  let(:dossier) { create(:dossier) }
  
  describe '#perform' do
    context 'quand le dossier est toujours en brouillon' do
      it 'envoie l\'email brouillon' do
        expect(DossierMailer).to receive(:with)
          .with(dossier: dossier)
          .and_return(double(notify_new_draft: double(deliver_now: true)))
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier est passé en construction' do
      before { dossier.en_construction! }
      
      it 'n\'envoie pas l\'email brouillon' do
        expect(DossierMailer).not_to receive(:with)
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier est en instruction' do
      before { dossier.en_instruction! }
      
      it 'n\'envoie pas l\'email brouillon' do
        expect(DossierMailer).not_to receive(:with)
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier est accepté' do
      before { dossier.accepte! }
      
      it 'n\'envoie pas l\'email brouillon' do
        expect(DossierMailer).not_to receive(:with)
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier n\'existe plus' do
      it 'ne lève pas d\'erreur' do
        expect { described_class.new.perform(999999) }.not_to raise_error
      end
      
      it 'n\'envoie pas d\'email' do
        expect(DossierMailer).not_to receive(:with)
        
        described_class.new.perform(999999)
      end
    end
  end
end