# frozen_string_literal: true

describe ChampPresentations::MultiplePieceJustificativePresentation do
  let(:blob1) { double('blob1', id: 1, filename: double('filename', to_s: 'image1.jpg'), content_type: 'image/jpeg') }
  let(:blob2) { double('blob2', id: 2, filename: double('filename', to_s: 'image2.jpg'), content_type: 'image/jpeg') }
  let(:blob3) { double('blob3', id: 3, filename: double('filename', to_s: 'document.pdf'), content_type: 'application/pdf') }

  let(:variant1) { double('variant1') }
  let(:variant2) { double('variant2') }
  let(:processed1) { double('processed1') }
  let(:processed2) { double('processed2') }

  let(:attachment1) do
    double('attachment1',
      blob: blob1,
      filename: blob1.filename,
      url: 'http://example.com/image1.jpg',
      image?: true,
      previewable?: true)
  end

  let(:attachment2) do
    double('attachment2',
      blob: blob2,
      filename: blob2.filename,
      url: 'http://example.com/image2.jpg',
      image?: true,
      previewable?: true)
  end

  let(:attachment3) do
    double('attachment3',
      blob: blob3,
      filename: blob3.filename,
      url: 'http://example.com/document.pdf',
      image?: false,
      previewable?: false)
  end

  before do
    # Mock variants pour images
    allow(attachment1).to receive(:variant).with(resize_to_limit: [400, 400]).and_return(variant1)
    allow(variant1).to receive(:processed).and_return(processed1)
    allow(processed1).to receive(:download).and_return("data1")

    allow(attachment2).to receive(:variant).with(resize_to_limit: [400, 400]).and_return(variant2)
    allow(variant2).to receive(:processed).and_return(processed2)
    allow(processed2).to receive(:download).and_return("data2")

    allow(Base64).to receive(:strict_encode64).with("data1").and_return("ZGF0YTE=")
    allow(Base64).to receive(:strict_encode64).with("data2").and_return("ZGF0YTI=")
  end

  describe '#to_tiptap_node' do
    context 'avec une seule pièce jointe' do
      subject { described_class.new([attachment1]) }

      it 'retourne structure simple sans paragraphe' do
        node = subject.to_tiptap_node
        expect(node[:type]).to eq('attachmentImage')
        expect(node[:attrs][:id]).to eq(1)
      end
    end

    context 'avec plusieurs pièces jointes images' do
      subject { described_class.new([attachment1, attachment2]) }

      it "retourne un paragraphe centré au lieu d'une bulletList" do
        node = subject.to_tiptap_node
        # pf: paragraphe au lieu de bulletList pour affichage côte à côte
        expect(node[:type]).to eq('paragraph')
        expect(node[:attrs][:textAlign]).to eq('center')
      end

      it 'contient les images séparées par des espaces' do
        node = subject.to_tiptap_node
        content = node[:content]

        # pf: vérifier structure [image, espace, image]
        expect(content.length).to eq(3)
        expect(content[0][:type]).to eq('attachmentImage')
        expect(content[1][:type]).to eq('text')
        expect(content[1][:text]).to eq(' ')
        expect(content[2][:type]).to eq('attachmentImage')
      end

      it 'chaque image a une data URI et "Télécharger"' do
        node = subject.to_tiptap_node
        content = node[:content]

        first_image = content[0]
        expect(first_image[:attrs][:src]).to eq('data:image/jpeg;base64,ZGF0YTE=')
        expect(first_image[:attrs][:display]).to eq('Télécharger')
        expect(first_image[:attrs][:alt]).to eq('image1.jpg')

        second_image = content[2]
        expect(second_image[:attrs][:src]).to eq('data:image/jpeg;base64,ZGF0YTI=')
        expect(second_image[:attrs][:display]).to eq('Télécharger')
        expect(second_image[:attrs][:alt]).to eq('image2.jpg')
      end
    end

    context 'avec mélange images et documents' do
      subject { described_class.new([attachment1, attachment3]) }

      it 'affiche paragraphe même avec types mixtes' do
        node = subject.to_tiptap_node
        expect(node[:type]).to eq('paragraph')
        expect(node[:attrs][:textAlign]).to eq('center')
      end

      it 'contient image et lien séparés par espace' do
        node = subject.to_tiptap_node
        content = node[:content]

        expect(content.length).to eq(3)
        expect(content[0][:type]).to eq('attachmentImage')
        expect(content[1][:text]).to eq(' ')
        expect(content[2][:type]).to eq('attachmentLink')
        expect(content[2][:content]).to eq([{ type: 'text', text: 'Télécharger' }])
      end
    end

    context 'avec trois images ou plus' do
      let(:blob4) { double('blob4', id: 4, filename: double('filename', to_s: 'image3.jpg'), content_type: 'image/jpeg') }
      let(:attachment4) do
        double('attachment4',
          blob: blob4,
          filename: blob4.filename,
          url: 'http://example.com/image3.jpg',
          image?: true,
          previewable?: true)
      end

      before do
        variant3 = double('variant3')
        processed3 = double('processed3')
        allow(attachment4).to receive(:variant).with(resize_to_limit: [400, 400]).and_return(variant3)
        allow(variant3).to receive(:processed).and_return(processed3)
        allow(processed3).to receive(:download).and_return("data3")
        allow(Base64).to receive(:strict_encode64).with("data3").and_return("ZGF0YTM=")
      end

      subject { described_class.new([attachment1, attachment2, attachment4]) }

      it 'affiche paragraphe avec espaces entre toutes les images' do
        node = subject.to_tiptap_node
        content = node[:content]

        # pf: [image, espace, image, espace, image] = 5 éléments
        expect(content.length).to eq(5)
        expect(content[0][:type]).to eq('attachmentImage')
        expect(content[1][:text]).to eq(' ')
        expect(content[2][:type]).to eq('attachmentImage')
        expect(content[3][:text]).to eq(' ')
        expect(content[4][:type]).to eq('attachmentImage')
      end
    end
  end

  describe '#block_level?' do
    it 'retourne true pour plusieurs PJ' do
      presentation = described_class.new([attachment1, attachment2])
      expect(presentation.block_level?).to be true
    end

    it 'retourne false pour une seule PJ' do
      presentation = described_class.new([attachment1])
      expect(presentation.block_level?).to be false
    end
  end

  describe '#to_s' do
    it 'concatène avec safe_join pour sécurité' do
      presentation = described_class.new([attachment1, attachment2])
      expect(ActionController::Base.helpers).to receive(:safe_join)
      presentation.to_s
    end
  end
end
