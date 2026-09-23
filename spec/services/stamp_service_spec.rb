# frozen_string_literal: true

describe StampService do
  let(:url) { 'https://www.mes-demarches.gov.pf/champs/1/2/piece_justificative/download/abc/0' }
  let(:blob) { double('blob') }

  before do
    file = Tempfile.new(['source', '.pdf'], binmode: true)
    file.write(source_pdf)
    file.rewind
    allow(blob).to receive(:open).and_yield(file)
  end

  def build_pdf
    doc = HexaPDF::Document.new
    page = doc.pages.add
    yield(doc, page) if block_given?
    io = StringIO.new(''.b)
    doc.write(io, validate: false)
    io.string
  end

  subject(:stamped) { HexaPDF::Document.new(io: StringIO.new(described_class.new.stamp(blob, url))) }

  context 'avec un PDF conforme' do
    let(:source_pdf) { build_pdf }

    it 'ajoute le lien de téléchargement sur la première page' do
      uris = stamped.pages[0][:Annots].map { |annot| annot[:A][:URI] }
      expect(uris).to include(url)
    end
  end

  context 'avec une police CID sans CIDSystemInfo (PDF non conforme)' do
    let(:source_pdf) do
      build_pdf do |doc, page|
        cid_font = doc.add({ Type: :Font, Subtype: :CIDFontType2, BaseFont: :Broken })
        type0 = doc.add({ Type: :Font, Subtype: :Type0, BaseFont: :Broken, Encoding: :'Identity-H', DescendantFonts: [cid_font] })
        page.resources[:Font] = { F1: type0 }
      end
    end

    it 'tamponne le document sans lever HexaPDF::Error' do
      uris = stamped.pages[0][:Annots].map { |annot| annot[:A][:URI] }
      expect(uris).to include(url)
    end
  end
end
