# frozen_string_literal: true

# pf: Tests spécifiques pour la génération QR code dans attestation v2
describe AttestationTemplate, '#generate_qrcode_svg' do
  let(:attestation_template) { create(:attestation_template, version: 2) }

  describe '#generate_qrcode_svg' do
    it 'génère un SVG QR code valide' do
      url = 'https://example.com/verify'
      svg = attestation_template.send(:generate_qrcode_svg, url)

      expect(svg).to be_present
      expect(svg).to include('<svg')
      expect(svg).to include('</svg>')
    end

    it 'retourne nil en cas d\'erreur' do
      # Test avec une URL invalide
      svg = attestation_template.send(:generate_qrcode_svg, nil)
      expect(svg).to be_nil
    end
  end

  describe '#build_v2_pdf avec QR code' do
    let(:procedure) { create(:procedure, :published) }
    let(:attestation_template) do
      create(:attestation_template, version: 2, procedure: procedure, json_body: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [{ "type" => "text", "text" => "Test attestation" }]
          }
        ]
      })
    end
    let(:dossier) { create(:dossier, :accepte, procedure: procedure) }

    before do
      # Mock pour éviter les problèmes d'encoded_date
      allow(dossier).to receive(:encoded_date).with(:created_at).and_return('test-date')
      allow(attestation_template).to receive(:qrcode_dossier_url).and_return('http://test.com/qr')
    end

    it 'inclut les variables QR code dans le rendu' do
      # Mock ApplicationController.render pour capturer les assigns
      rendered_assigns = nil
      allow(ApplicationController).to receive(:render) do |args|
        rendered_assigns = args[:assigns]
        '<html>Mock rendered content</html>'
      end

      allow(WeasyprintService).to receive(:generate_pdf).and_return('mock pdf')

      attestation_template.send(:build_v2_pdf, dossier)

      expect(rendered_assigns).to include(:qrcode_url, :qrcode_svg)
      expect(rendered_assigns[:qrcode_url]).to eq('http://test.com/qr')
      expect(rendered_assigns[:qrcode_svg]).to be_present
    end
  end
end
