# frozen_string_literal: true

describe ChampPresentations::PieceJustificativePresentation do
  let(:blob) { double('blob', id: 456, filename: double('filename', to_s: 'test.pdf')) }
  let(:attachment) { double('attachment', id: 123, blob: blob, filename: blob.filename, url: 'http://example.com/test.pdf') }

  describe '#to_tiptap_node' do
    context 'pour un document' do
      subject { described_class.new(attachment, is_image: false) }

      it 'génère un nœud attachmentLink avec blob.id' do
        node = subject.to_tiptap_node
        expect(node['type']).to eq('attachmentLink')
        expect(node['attrs']['href']).to eq('http://example.com/test.pdf')
        expect(node['content']).to eq([{ 'type' => 'text', 'text' => 'test.pdf' }])
      end

      it 'utilise le blob.id comme identifiant' do
        presentation = described_class.new(attachment, is_image: false)
        expect(presentation.instance_variable_get(:@attachment_id)).to eq(456)
      end
    end

    context 'pour une image' do
      let(:image_blob) { double('blob', id: 789, filename: double('filename', to_s: 'image.jpg')) }
      let(:image_attachment) { double('attachment', id: 123, blob: image_blob, filename: image_blob.filename, url: 'http://example.com/image.jpg') }
      subject { described_class.new(image_attachment, is_image: true) }

      it 'génère un nœud attachmentImage avec blob.id' do
        node = subject.to_tiptap_node
        expect(node['type']).to eq('attachmentImage')
        expect(node['attrs']['id']).to eq(789) # blob.id
        expect(node['attrs']['src']).to eq('http://example.com/image.jpg')
        expect(node['attrs']['alt']).to eq('image.jpg')
        expect(node['attrs']['display']).to eq('image.jpg')
      end
    end
  end

  describe 'URLs permanentes' do
    let(:champ) { double('champ', dossier_id: 456, stable_id: 789, row_id: nil) }
    let(:type_de_champ) { double('type_de_champ') }

    before do
      allow(champ).to receive(:encoded_date).with(:created_at).and_return('abc123')
      allow(Rails.application.routes.url_helpers).to receive(:champs_piece_justificative_download_url)
        .with({ dossier_id: 456, stable_id: 789, h: 'abc123', i: 0, row_id: nil })
        .and_return('https://permanent.url/download?h=abc123')
    end

    it 'génère URL permanente quand champ présent' do
      presentation = described_class.new(attachment, is_image: false, champ: champ, index: 0)
      expect(presentation.instance_variable_get(:@url)).to eq('https://permanent.url/download?h=abc123')
    end

    it 'utilise URL éphémère quand pas de champ' do
      presentation = described_class.new(attachment, is_image: false)
      expect(presentation.instance_variable_get(:@url)).to eq('http://example.com/test.pdf')
    end
  end

  describe 'proxy développement pour images' do
    let(:image_blob) { double('blob', id: 999, filename: double('filename', to_s: 'dev-image.jpg')) }
    let(:dev_attachment) { double('attachment', id: 123, blob: image_blob, filename: image_blob.filename, url: 'http://example.com/dev-image.jpg') }

    before do
      allow(Rails.env).to receive(:development?).and_return(true)
      allow(Rails.application.routes.url_helpers).to receive(:attestation_images_proxy_path)
        .with(blob_id: 999)
        .and_return('/proxy/images/999')
    end

    it 'utilise proxy en développement pour images' do
      presentation = described_class.new(dev_attachment, is_image: true)
      expect(presentation.instance_variable_get(:@url)).to eq('/proxy/images/999')
    end

    it 'ignore proxy pour documents même en développement' do
      presentation = described_class.new(dev_attachment, is_image: false)
      expect(presentation.instance_variable_get(:@url)).to eq('http://example.com/dev-image.jpg')
    end
  end

  describe '.from_attachment' do
    context 'avec une image' do
      before do
        allow(attachment).to receive(:image?).and_return(true)
      end

      it 'crée une présentation image' do
        presentation = described_class.from_attachment(attachment)
        expect(presentation.instance_variable_get(:@is_image)).to be true
      end

      it 'accepte paramètres champ et index' do
        champ = double('champ', dossier_id: 999, stable_id: 888, row_id: nil)
        allow(champ).to receive(:encoded_date).with(:created_at).and_return('test123')
        allow(Rails.application.routes.url_helpers).to receive(:champs_piece_justificative_download_url)
          .and_return('https://test.com/download')

        presentation = described_class.from_attachment(attachment, champ: champ, index: 2)
        expect(presentation.instance_variable_get(:@champ)).to eq(champ)
        expect(presentation.instance_variable_get(:@index)).to eq(2)
      end
    end

    context 'avec un document' do
      before do
        allow(attachment).to receive(:image?).and_return(false)
      end

      it 'crée une présentation document' do
        presentation = described_class.from_attachment(attachment)
        expect(presentation.instance_variable_get(:@is_image)).to be false
      end
    end
  end
end
