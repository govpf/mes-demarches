# frozen_string_literal: true

describe MailTemplatePresenterService do
  let(:procedure) { create(:simple_procedure) }
  let(:dossier) { create(:dossier, :accepte, procedure: procedure, motivation: motivation) }
  let(:closed_mail) { create(:closed_mail, procedure: procedure, body: body) }

  before do
    procedure.closed_mail = closed_mail
  end

  describe '#safe_body' do
    let(:service) { MailTemplatePresenterService.new(dossier, Dossier.states.fetch(:accepte)) }

    context 'when motivation contains HTML links (pf: download links from instructeurs)' do
      let(:motivation) { 'Décision acceptée. Télécharger le document : <a href="https://example.pf/doc.pdf">Document officiel</a>' }
      let(:body) { 'Votre dossier a été accepté. Motif : --motivation--' }

      it 'preserves existing HTML links' do
        result = service.safe_body
        expect(result).to include('<a href="https://example.pf/doc.pdf">Document officiel</a>')
      end

      it 'wraps content in paragraphs' do
        result = service.safe_body
        expect(result).to match(/<p>.*<\/p>/m)
      end
    end

    context 'when motivation contains raw URLs (pf: auto-link bare URLs)' do
      let(:motivation) { 'Voir le site : https://www.service-public.pf pour plus d\'infos' }
      let(:body) { 'Motivation : --motivation--' }

      it 'converts raw URLs to clickable links' do
        result = service.safe_body
        expect(result).to include('<a ')
        expect(result).to include('href="https://www.service-public.pf"')
        expect(result).to include('target="_blank"')
        expect(result).to include('rel="noopener"')
      end
    end

    context 'when motivation contains both HTML links and raw URLs (pf: best of both worlds)' do
      let(:motivation) do
        'Document : <a href="https://example.pf/doc.pdf">Télécharger</a> et voir https://www.service-public.pf'
      end
      let(:body) { '--motivation--' }

      it 'preserves HTML links and converts raw URLs' do
        result = service.safe_body

        # Lien HTML existant préservé
        expect(result).to include('<a href="https://example.pf/doc.pdf">Télécharger</a>')

        # URL brute convertie en lien
        expect(result).to include('href="https://www.service-public.pf"')
      end
    end

    context 'when motivation contains images (pf: preserve instructor images)' do
      let(:motivation) { 'Logo : <img src="https://example.pf/logo.png" alt="Logo" />' }
      let(:body) { '--motivation--' }

      it 'preserves images' do
        result = service.safe_body
        expect(result).to include('<img')
        expect(result).to include('src="https://example.pf/logo.png"')
      end
    end

    context 'when motivation contains dangerous HTML (pf: sanitization)' do
      let(:motivation) { 'Voir <script>alert("xss")</script> et <iframe src="evil.com"></iframe>' }
      let(:body) { '--motivation--' }

      it 'removes dangerous tags' do
        result = service.safe_body
        expect(result).not_to include('<script')
        expect(result).not_to include('<iframe')
      end
    end
  end
end
