# frozen_string_literal: true

describe ChampPresentations::PieceJustificativePresentation do
  let(:blob) { double('blob', id: 456, filename: double('filename', to_s: 'test.pdf'), content_type: 'application/pdf') }
  let(:attachment) { double('attachment', id: 123, blob: blob, filename: blob.filename, url: 'http://example.com/test.pdf', image?: false, previewable?: false) }

  describe '#to_tiptap_node' do
    context 'pour un document non-previewable' do
      subject { described_class.new(attachment, is_previewable: false) }

      it 'génère un nœud attachmentLink avec attachment.id' do
        node = subject.to_tiptap_node
        expect(node[:type]).to eq('attachmentLink')
        expect(node[:attrs][:href]).to eq('http://example.com/test.pdf')
        # pf: texte "Télécharger [nom]" pour les documents non-previewable
        expect(node[:content]).to eq([{ type: 'text', text: 'Télécharger test.pdf' }])
      end

      it 'utilise l\'attachment.id comme identifiant' do
        presentation = described_class.new(attachment, is_previewable: false)
        expect(presentation.instance_variable_get(:@attachment_id)).to eq(123)
      end
    end

    context 'pour une image previewable' do
      let(:image_blob) { double('blob', id: 789, filename: double('filename', to_s: 'image.jpg'), content_type: 'image/jpeg') }
      let(:variant) { double('variant') }
      let(:processed_variant) { double('processed_variant') }
      let(:image_attachment) do
        double('attachment',
          id: 123,
          blob: image_blob,
          filename: image_blob.filename,
          url: 'http://example.com/image.jpg',
          image?: true,
          previewable?: true)
      end

      before do
        # Mock la génération de data URI
        allow(image_attachment).to receive(:variant).with(resize_to_limit: [400, 400]).and_return(variant)
        allow(variant).to receive(:processed).and_return(processed_variant)
        allow(processed_variant).to receive(:download).and_return("fake_image_data")
        allow(Base64).to receive(:strict_encode64).with("fake_image_data").and_return("ZmFrZV9pbWFnZV9kYXRh")
      end

      subject { described_class.new(image_attachment, is_previewable: true) }

      it 'génère un nœud attachmentImage avec data URI' do
        node = subject.to_tiptap_node
        expect(node[:type]).to eq('attachmentImage')
        expect(node[:attrs][:id]).to eq(123) # attachment.id (requis par Prawn)
        # pf: vérifier que src est un data URI
        expect(node[:attrs][:src]).to start_with('data:image/')
        expect(node[:attrs][:src]).to include(';base64,')
        # pf: alt contient le nom du fichier pour accessibilité
        expect(node[:attrs][:alt]).to eq('image.jpg')
        # pf: display contient "Télécharger"
        expect(node[:attrs][:display]).to eq('Télécharger')
      end

      it 'génère une data URI base64 complète' do
        node = subject.to_tiptap_node
        expect(node[:attrs][:src]).to eq('data:image/jpeg;base64,ZmFrZV9pbWFnZV9kYXRh')
      end
    end

    context 'pour un PDF previewable' do
      let(:pdf_blob) { double('blob', id: 999, filename: double('filename', to_s: 'document.pdf'), content_type: 'application/pdf') }
      let(:preview) { double('preview') }
      let(:processed_preview) { double('processed_preview') }
      let(:pdf_attachment) do
        double('attachment',
          id: 124,
          blob: pdf_blob,
          filename: pdf_blob.filename,
          url: 'http://example.com/document.pdf',
          image?: false,
          previewable?: true)
      end

      before do
        # Mock la génération de preview pour PDF
        allow(pdf_attachment).to receive(:preview).with(resize_to_limit: [400, 400]).and_return(preview)
        allow(preview).to receive(:processed).and_return(processed_preview)
        allow(processed_preview).to receive(:download).and_return("fake_preview_data")
        allow(Base64).to receive(:strict_encode64).with("fake_preview_data").and_return("ZmFrZV9wcmV2aWV3X2RhdGE=")
      end

      subject { described_class.new(pdf_attachment, is_previewable: true) }

      it 'génère un nœud attachmentImage avec preview en PNG' do
        node = subject.to_tiptap_node
        expect(node[:type]).to eq('attachmentImage')
        # pf: les previews sont toujours en PNG
        expect(node[:attrs][:src]).to eq('data:image/png;base64,ZmFrZV9wcmV2aWV3X2RhdGE=')
        expect(node[:attrs][:alt]).to eq('document.pdf')
        expect(node[:attrs][:display]).to eq('Télécharger')
      end
    end
  end

  describe 'URLs permanentes' do
    let(:champ) { double('champ', dossier_id: 456, stable_id: 789, row_id: nil) }

    before do
      allow(champ).to receive(:encoded_date).with(:created_at).and_return('abc123')
      allow(Rails.application.routes.url_helpers).to receive(:champs_piece_justificative_download_url)
        .with({ dossier_id: 456, stable_id: 789, h: 'abc123', i: 0, row_id: nil })
        .and_return('https://permanent.url/download?h=abc123')
    end

    it 'génère URL permanente quand champ présent' do
      presentation = described_class.new(attachment, is_previewable: false, champ: champ, index: 0)
      expect(presentation.instance_variable_get(:@url)).to eq('https://permanent.url/download?h=abc123')
    end

    it 'utilise URL éphémère quand pas de champ' do
      presentation = described_class.new(attachment, is_previewable: false)
      expect(presentation.instance_variable_get(:@url)).to eq('http://example.com/test.pdf')
    end
  end

  describe '.from_attachment' do
    context 'avec une image' do
      let(:test_blob) { double('blob', id: 111, filename: double('filename', to_s: 'test.jpg'), content_type: 'image/jpeg') }
      let(:test_variant) { double('variant') }
      let(:test_processed) { double('processed') }
      let(:test_attachment) do
        double('attachment',
          id: 555,
          blob: test_blob,
          filename: double('filename', to_s: 'test.jpg'),
          url: 'http://example.com/test.jpg',
          image?: true,
          previewable?: true)
      end

      before do
        allow(test_attachment).to receive(:variant).with(resize_to_limit: [400, 400]).and_return(test_variant)
        allow(test_variant).to receive(:processed).and_return(test_processed)
        allow(test_processed).to receive(:download).and_return("data")
        allow(Base64).to receive(:strict_encode64).with("data").and_return("ZGF0YQ==")
      end

      it 'crée une présentation previewable' do
        presentation = described_class.from_attachment(test_attachment)
        expect(presentation.instance_variable_get(:@is_previewable)).to be true
      end

      it 'accepte paramètres champ et index' do
        champ = double('champ', dossier_id: 999, stable_id: 888, row_id: nil)
        allow(champ).to receive(:encoded_date).with(:created_at).and_return('test123')
        allow(Rails.application.routes.url_helpers).to receive(:champs_piece_justificative_download_url)
          .and_return('https://test.com/download')

        presentation = described_class.from_attachment(test_attachment, champ: champ, index: 2)
        expect(presentation.instance_variable_get(:@champ)).to eq(champ)
        expect(presentation.instance_variable_get(:@index)).to eq(2)
      end
    end

    context 'avec un PDF previewable' do
      let(:pdf_blob) { double('blob', id: 222, filename: double('filename', to_s: 'document.pdf'), content_type: 'application/pdf') }
      let(:pdf_preview) { double('preview') }
      let(:pdf_processed) { double('processed') }
      let(:pdf_attachment) do
        double('attachment',
          id: 111,
          blob: pdf_blob,
          filename: double('filename', to_s: 'document.pdf'),
          url: 'http://example.com/document.pdf',
          image?: false,
          previewable?: true)
      end

      before do
        allow(pdf_attachment).to receive(:preview).with(resize_to_limit: [400, 400]).and_return(pdf_preview)
        allow(pdf_preview).to receive(:processed).and_return(pdf_processed)
        allow(pdf_processed).to receive(:download).and_return("preview_data")
        allow(Base64).to receive(:strict_encode64).with("preview_data").and_return("cHJldmlld19kYXRh")
      end

      it 'crée une présentation previewable même pour PDF' do
        presentation = described_class.from_attachment(pdf_attachment)
        expect(presentation.instance_variable_get(:@is_previewable)).to be true
      end
    end

    context 'avec un document non-previewable' do
      let(:doc_attachment) do
        double('attachment',
          id: 444,
          blob: double('blob', id: 333, filename: double('filename', to_s: 'archive.zip'), content_type: 'application/zip'),
          filename: double('filename', to_s: 'archive.zip'),
          url: 'http://example.com/archive.zip',
          image?: false,
          previewable?: false)
      end

      it 'crée une présentation non-previewable' do
        presentation = described_class.from_attachment(doc_attachment)
        expect(presentation.instance_variable_get(:@is_previewable)).to be false
      end
    end
  end

  describe 'gestion erreurs data URI' do
    let(:image_blob) { double('blob', id: 789, filename: double('filename', to_s: 'broken.jpg'), content_type: 'image/jpeg') }
    let(:image_attachment) do
      double('attachment',
        id: 123,
        blob: image_blob,
        filename: image_blob.filename,
        url: 'http://example.com/broken.jpg',
        image?: true,
        previewable?: true)
    end

    before do
      # Simuler une erreur lors de la génération
      allow(image_attachment).to receive(:variant).and_raise(StandardError, "Image processing failed")
    end

    subject { described_class.new(image_attachment, is_previewable: true) }

    it 'fallback sur lien de téléchargement en cas d erreur' do
      node = subject.to_tiptap_node
      # pf: si preview échoue, retourner attachmentLink au lieu d'attachmentImage
      expect(node[:type]).to eq('attachmentLink')
      expect(node[:attrs][:href]).to eq('http://example.com/broken.jpg')
      expect(node[:content]).to eq([{ type: 'text', text: 'Télécharger broken.jpg' }])
    end
  end
end
