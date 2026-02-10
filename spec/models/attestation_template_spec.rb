# frozen_string_literal: true

describe AttestationTemplate, type: :model do
  describe 'validates footer length' do
    let(:attestation_template) { build(:attestation_template, footer: footer) }

    subject do
      attestation_template.validate
      attestation_template.errors.details
    end

    context 'when the footer is too long' do
      let(:footer) { 'a' * 191 }

      it { is_expected.to match({ footer: [{ error: :too_long, count: 190 }] }) }
    end
  end

  describe 'dup' do
    let(:attestation_template) { create(:attestation_template, attributes) }
    subject { attestation_template.dup }

    context 'with an attestation without images' do
      let(:attributes) { attributes_for(:attestation_template) }

      it "works" do
        is_expected.to have_attributes(attributes)
        is_expected.to have_attributes(id: nil)
        expect(subject.logo.attached?).to be_falsey
      end
    end

    context 'with an attestation with images' do
      let(:attestation_template) { create(:attestation_template, :with_files) }

      it do
        expect(subject.logo.attachment).not_to eq(attestation_template.logo.attachment)
        expect(subject.logo.blob).to eq(attestation_template.logo.blob)
        expect(subject.logo.attached?).to be_truthy
      end

      it do
        expect(subject.signature.attachment).not_to eq(attestation_template.signature.attachment)
        expect(subject.signature.blob).to eq(attestation_template.signature.blob)
        expect(subject.signature.attached?).to be_truthy
      end
    end
  end

  describe 'invalidate attestation if images attachments are not valid' do
    subject { build(:attestation_template, :with_gif_files) }

    context 'with an attestation which has gif files' do
      it { is_expected.not_to be_valid }
    end
  end

  describe 'attestation_for' do
    let(:procedure) do
      create(:procedure,
        types_de_champ_public: types_de_champ,
        types_de_champ_private: types_de_champ_private,
        attestation_template: attestation_template)
    end
    let(:etablissement) { create(:etablissement) }
    let(:types_de_champ) { [] }
    let(:types_de_champ_private) { [] }
    let(:dossier) { create(:dossier, :accepte, procedure:) }

    let(:types_de_champ) do
      [
        { libelle: 'libelleA' },
        { libelle: 'libelleB' }
      ]
    end

    before do
      dossier.project_champs_public
        .find { |champ| champ.libelle == 'libelleA' }
        .update(value: 'libelle1')

      dossier.project_champs_public
        .find { |champ| champ.libelle == 'libelleB' }
        .update(value: 'libelle2')
    end

    let(:attestation) { attestation_template.attestation_for(dossier) }

    context 'attestation v1' do
      let(:template_title) { 'title --libelleA--' }
      let(:template_body) { 'body --libelleB--' }
      let(:attestation_template) do
        build(:attestation_template,
          title: template_title,
          body: template_body)
      end

      let(:view_args) do
        arguments = nil

        allow(ApplicationController).to receive(:render).and_wrap_original do |m, *args|
          arguments = args.first[:assigns]
          m.call(*args)
        end

        attestation_template.attestation_for(dossier)

        arguments
      end

      it 'passes the correct parameters and generates an attestation' do
        expect(view_args[:attestation][:title]).to eq('title libelle1')
        expect(view_args[:attestation][:body]).to eq('body libelle2')
        expect(attestation.title).to eq('title libelle1')
        expect(attestation.pdf).to be_attached
      end
    end

    context 'attestation v2' do
      let(:attestation_template) do
        build(:attestation_template, :v2, :with_files, label_logo: "Ministère des specs")
      end

      before do
        stub_request(:post, WEASYPRINT_URL)
          .with(body: {
            html: /Ministère des specs.+Mon titre pour #{procedure.libelle}.+Dossier: n° #{dossier.id}/m,
            upstream_context: { procedure_id: procedure.id, dossier_id: dossier.id }
          })
          .to_return(body: 'PDF_DATA')
      end

      it 'generates an attestation' do
        expect(attestation.pdf).to be_attached
      end
    end
  end

  describe '#render_attributes_for' do
    context 'signature' do
      let(:dossier) { create(:dossier, procedure: attestation.procedure, groupe_instructeur: groupe_instructeur) }

      subject { attestation.render_attributes_for(dossier: dossier)[:signature] }

      context 'procedure with signature' do
        let(:attestation) { create(:attestation_template, signature: Rack::Test::UploadedFile.new('spec/fixtures/files/logo_test_procedure.png', 'image/png')) }

        context "groupe instructeur without signature" do
          let(:groupe_instructeur) { create(:groupe_instructeur, signature: nil) }

          it { expect(subject).to be_an_instance_of(ActiveStorage::Attached::One) }
        end

        context 'groupe instructeur with signature' do
          let(:groupe_instructeur) { create(:groupe_instructeur, signature: Rack::Test::UploadedFile.new('spec/fixtures/files/black.png', 'image/png')) }

          it { expect(subject).to be_an_instance_of(ActiveStorage::Attached::One) }
        end
      end

      context 'procedure without signature' do
        let(:attestation) { create(:attestation_template, signature: nil) }

        context "groupe instructeur without signature" do
          let(:groupe_instructeur) { create(:groupe_instructeur, signature: nil) }

          it { expect(subject.blob).to be_nil }
        end
      end
    end

    context 'body v2' do
      let(:attestation) { create(:attestation_template, :v2) }
      let(:dossier) { create(:dossier, procedure: attestation.procedure, individual: build(:individual, nom: 'Doe', prenom: 'John')) }

      it do
        body = attestation.render_attributes_for(dossier: dossier)[:body]
        expect(body).to include("Mon titre pour #{dossier.procedure.libelle}")
        expect(body).to include("Doe John")
      end
    end
  end

  describe 'Migration v1 vers v2' do
    let(:v1_template) do
      create(:attestation_template,
        version: 1,
        title: 'Titre avec <b>formatage</b>',
        body: 'Corps avec <i>italique</i> et <u>souligné</u>',
        footer: 'Pied de page',
        activated: true)
    end
    let(:procedure) { v1_template.procedure }

    describe '#build_v2_from_v1' do
      context 'avec contenu HTML simple' do
        it 'convertit correctement le formatage basique' do
          v2_template = procedure.build_attestation_template_v2_from_v1(v1_template)

          expect(v2_template.version).to eq(2)
          expect(v2_template.footer).to eq(v1_template.footer)
          expect(v2_template.activated).to eq(v1_template.activated)

          # Vérifie la structure JSON Tiptap
          json_body = JSON.parse(v2_template.tiptap_body)
          expect(json_body['type']).to eq('doc')
          expect(json_body['content']).to be_an(Array)
        end

        it 'préserve l\'état d\'activation' do
          v1_template.update!(activated: false)
          v2_template = procedure.build_attestation_template_v2_from_v1(v1_template)

          expect(v2_template.activated).to be false
        end

        it 'crée un template draft pour procédure publiée' do
          procedure.update!(aasm_state: :publiee)
          v2_template = procedure.build_attestation_template_v2_from_v1(v1_template)

          expect(v2_template.state).to eq('draft')
        end

        it 'crée un template published pour procédure brouillon' do
          procedure.update!(aasm_state: :brouillon)
          v2_template = procedure.build_attestation_template_v2_from_v1(v1_template)

          expect(v2_template.state).to eq('published')
        end
      end

      context 'avec attachments' do
        let(:logo) { fixture_file_upload('spec/fixtures/files/white.png', 'image/png') }
        let(:signature) { fixture_file_upload('spec/fixtures/files/black.png', 'image/png') }
        let(:v1_template) do
          create(:attestation_template,
            version: 1,
            title: 'Titre simple',
            body: 'Corps simple',
            activated: true,
            logo: logo,
            signature: signature)
        end

        it 'copie les attachments' do
          v2_template = procedure.build_attestation_template_v2_from_v1(v1_template)
          v2_template.save!

          expect(v2_template.logo).to be_attached
          expect(v2_template.signature).to be_attached

          # Vérifie que ce sont des copies, pas des déplacements
          expect(v1_template.reload.logo).to be_attached
          expect(v1_template.reload.signature).to be_attached

          # Vérifie que les blobs sont partagés (même fichier)
          expect(v2_template.logo.blob).to eq(v1_template.logo.blob)
          expect(v2_template.signature.blob).to eq(v1_template.signature.blob)
        end

        it 'désactive official_layout si logo présent' do
          v2_template = procedure.build_attestation_template_v2_from_v1(v1_template)
          expect(v2_template.official_layout).to be false
        end
      end

      context 'sans logo' do
        let(:v1_template) do
          create(:attestation_template,
            version: 1,
            title: 'Titre simple',
            body: 'Corps simple',
            activated: true)
        end

        it 'active official_layout si pas de logo' do
          v2_template = procedure.build_attestation_template_v2_from_v1(v1_template)
          expect(v2_template.official_layout).to be true
        end
      end

      context 'sans contenu v1' do
        let(:v1_template) do
          create(:attestation_template,
            version: 1,
            title: nil,
            body: nil,
            activated: false)
        end

        it 'crée un template v2 valide avec contenu par défaut' do
          v2_template = procedure.build_attestation_template_v2_from_v1(v1_template)

          json_body = JSON.parse(v2_template.tiptap_body)
          expect(json_body['type']).to eq('doc')
          expect(json_body['content']).to be_an(Array)
          expect(v2_template.activated).to be false
        end
      end
    end

    describe '#html_to_tiptap_basic' do
      let(:converter) { v1_template }

      it 'convertit les balises gras' do
        result = converter.send(:html_to_tiptap_basic, '<b>gras</b>')
        expected = [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'gras', 'marks' => [{ 'type' => 'bold' }] }] }]
        expect(result).to eq(expected)
      end

      it 'convertit les balises italique' do
        result = converter.send(:html_to_tiptap_basic, '<i>italique</i>')
        expected = [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'italique', 'marks' => [{ 'type' => 'italic' }] }] }]
        expect(result).to eq(expected)
      end

      it 'convertit les balises soulignées' do
        result = converter.send(:html_to_tiptap_basic, '<u>souligné</u>')
        expected = [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'souligné', 'marks' => [{ 'type' => 'underline' }] }] }]
        expect(result).to eq(expected)
      end

      it 'convertit les balises strong et em' do
        result = converter.send(:html_to_tiptap_basic, '<strong>fort</strong> et <em>emphase</em>')
        expected = [
          {
            'type' => 'paragraph',
                    'content' => [
                      { 'type' => 'text', 'text' => 'fort', 'marks' => [{ 'type' => 'bold' }] },
                      { 'type' => 'text', 'text' => ' et ' },
                      { 'type' => 'text', 'text' => 'emphase', 'marks' => [{ 'type' => 'italic' }] }
                    ]
          }
        ]
        expect(result).to eq(expected)
      end

      it 'gère le formatage combiné' do
        result = converter.send(:html_to_tiptap_basic, '<b><i>gras et italique</i></b>')
        expected = [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'gras et italique', 'marks' => [{ 'type' => 'italic' }, { 'type' => 'bold' }] }] }]
        expect(result).to eq(expected)
      end

      it 'préserve le texte sans formatage' do
        result = converter.send(:html_to_tiptap_basic, 'texte simple')
        expected = [{ 'type' => 'paragraph', 'content' => [{ 'type' => 'text', 'text' => 'texte simple' }] }]
        expect(result).to eq(expected)
      end

      it 'ignore les balises non supportées' do
        result = converter.send(:html_to_tiptap_basic, '<font color="red">texte coloré</font>')
        # Les balises non supportées deviennent du texte brut
        expect(result.first['type']).to eq('paragraph')
        expect(result.first['content'].first['text']).to include('texte coloré')
        expect(result.first['content'].first['marks']).to be_nil
      end

      it 'gère les sauts de ligne en créant des paragraphes séparés' do
        result = converter.send(:html_to_tiptap_basic, "ligne1\n\nligne2")
        # Nouvelle approche : chaque ligne = un paragraphe
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        expect(result[0]['type']).to eq('paragraph')
        expect(result[0]['content'][0]['text']).to eq('ligne1')
        expect(result[1]['type']).to eq('paragraph')
        expect(result[1]['content'][0]['text']).to eq('ligne2')
      end
    end

    describe '#html_to_tiptap_inline' do
      let(:converter) { v1_template }

      it 'retourne du contenu inline sans paragraphe' do
        result = converter.send(:html_to_tiptap_inline, '<b>titre gras</b>')
        expected = [{ 'type' => 'text', 'text' => 'titre gras', 'marks' => [{ 'type' => 'bold' }] }]
        expect(result).to eq(expected)
      end

      it 'traite le texte simple en inline' do
        result = converter.send(:html_to_tiptap_inline, 'titre simple')
        expected = [{ 'type' => 'text', 'text' => 'titre simple' }]
        expect(result).to eq(expected)
      end

      it 'ignore les retours à la ligne en mode inline' do
        result = converter.send(:html_to_tiptap_inline, "ligne1\nligne2")
        # En mode inline, pas de paragraphes séparés
        expect(result).to be_an(Array)
        expect(result.first['type']).to eq('text')
      end
    end

    describe 'validation de la migration' do
      it 'détecte les balises HTML présentes' do
        template_with_html = create(:attestation_template,
          version: 1,
          body: 'Texte avec <b>gras</b> et <table><tr><td>tableau</td></tr></table>')

        analysis = template_with_html.analyze_v1_content
        expect(analysis[:has_basic_formatting]).to be true
        expect(analysis[:has_tables]).to be true
        expect(analysis[:basic_tags]).to include('b')
        expect(analysis[:table_count]).to eq(1)
      end

      it 'détecte l\'absence de formatage' do
        template_plain = create(:attestation_template,
          version: 1,
          body: 'Texte simple sans formatage')

        analysis = template_plain.analyze_v1_content
        expect(analysis[:has_basic_formatting]).to be false
        expect(analysis[:has_tables]).to be false
        expect(analysis[:basic_tags]).to be_empty
        expect(analysis[:table_count]).to eq(0)
      end
    end
  end
end
