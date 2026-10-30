# frozen_string_literal: true

RSpec.describe Dossiers::EditFooterComponent, type: :component do
  let(:annotation) { false }
  let(:component) { described_class.new(dossier:, annotation:) }

  subject { render_inline(component).to_html }

  before do
    allow(component).to receive(:owner?).and_return(true)
    allow(component).to receive(:show_for_user?).and_return(true)
  end

  context 'when brouillon' do
    let(:dossier) { create(:dossier, :brouillon) }

    context 'when dossier can be submitted' do
      before { allow(component).to receive(:can_passer_en_construction?).and_return(true) }

      it 'renders submit button without disabled' do
        expect(subject).to have_selector('button', text: 'Déposer le dossier')
      end
    end

    context 'when dossier can not be submitted' do
      before { allow(component).to receive(:can_passer_en_construction?).and_return(false) }

      it 'renders submit button with disabled, and the link opening the explanation on click only' do
        expect(subject).to have_selector("a[data-fr-opened='false']", text: 'Pourquoi je ne peux pas déposer mon dossier ?')
        expect(subject).to have_selector('button[disabled]', text: 'Déposer le dossier')
      end
    end

    context 'when rendered in instructeur context' do
      before { allow(component).to receive(:show_for_user?).and_return(false) }

      it 'does not render user actions' do
        expect(subject).not_to include('Déposer le dossier')
        expect(subject).not_to include('Vérifier la complétude')
      end
    end
  end

  context 'when en construction' do
    let(:dossier) { create(:dossier, :en_construction) }
    before { allow(dossier).to receive(:user_buffer_changes?).and_return(true) }

    context 'when dossier can be submitted' do
      before { allow(component).to receive(:can_passer_en_construction?).and_return(true) }

      it 'renders submit button without disabled' do
        expect(subject).to have_selector('button', text: 'Déposer les modifications')
      end
    end

    context 'when dossier can not be submitted' do
      before { allow(component).to receive(:can_passer_en_construction?).and_return(false) }

      it 'renders submit button with disabled' do
        expect(subject).to have_selector('a', text: 'Pourquoi je ne peux pas déposer mon dossier ?')
        expect(subject).to have_selector('button[disabled]', text: 'Déposer les modifications')
      end
    end
  end

  # pf: le stub de show_for_user? ci-dessus ne couvre pas le panneau des annotations
  # privées, où l'instructeur n'est pas propriétaire du dossier
  context 'when rendered in the private annotations panel' do
    let(:dossier) { create(:dossier, :en_construction) }
    let(:annotation) { true }

    before do
      allow(component).to receive(:owner?).and_return(false)
      allow(component).to receive(:show_for_user?).and_call_original
    end

    it 'does not render the invite actions nor the invite notice' do
      expect(subject).to include('Vos annotations sont automatiquement enregistrées.')
      expect(subject).not_to include('Vérifier le dossier')
      expect(subject).not_to include('le titulaire du dossier doit le déposer')
    end
  end
end
