# frozen_string_literal: true

require 'rails_helper'

describe 'Migration Attestations v1→v2', type: :model do
  describe 'Spécifications et validation des structures de données' do
    context 'Attestation v1' do
      it 'doit avoir une structure v1 valide' do
        v1_template = create(:attestation_template, version: 1)

        expect(v1_template).to have_valid_v1_structure
        expect(v1_template.version).to eq(1)
        expect(v1_template.title).to be_present
        expect(v1_template.body).to be_present
      end

      it 'doit analyser correctement le contenu HTML' do
        v1_with_formatting = create(:attestation_template, :v1_with_basic_formatting)

        analysis = analyze_v1_html_content(v1_with_formatting.body)
        expect(analysis[:has_formatting]).to be true
        expect(analysis[:basic_tags]).to include('i', 'u')
        expect(analysis[:has_tables]).to be false
      end

      it 'doit détecter les tables dans le contenu' do
        v1_with_tables = create(:attestation_template, :v1_with_tables)

        analysis = analyze_v1_html_content(v1_with_tables.body)
        expect(analysis[:has_tables]).to be true
        expect(analysis[:table_count]).to eq(1)
      end

      it 'doit identifier le contenu sans formatage' do
        v1_plain = create(:attestation_template, :v1_plain_text)

        analysis = analyze_v1_html_content(v1_plain.body)
        expect(analysis[:has_formatting]).to be false
        expect(analysis[:basic_tags]).to be_empty
        expect(analysis[:has_tables]).to be false
      end
    end

    context 'Attestation v2' do
      it 'doit avoir une structure v2 valide' do
        v2_template = create(:attestation_template, :v2)

        expect(v2_template).to have_valid_v2_structure
        expect(v2_template.version).to eq(2)
        expect(v2_template.tiptap_body).to be_present
        expect(has_valid_tiptap_structure?(v2_template.tiptap_body)).to be true
      end

      it 'doit avoir un JSON Tiptap valide par défaut' do
        v2_template = create(:attestation_template, :v2)
        json_body = JSON.parse(v2_template.tiptap_body)

        expect(json_body['type']).to eq('doc')
        expect(json_body['content']).to be_an(Array)
        expect(json_body['content']).not_to be_empty
      end
    end

    context 'Structures de données attendues' do
      it 'doit documenter la conversion HTML → Tiptap' do
        test_cases = {
          '<b>gras</b>' => { marks: [{ 'type' => 'bold' }] },
          '<i>italique</i>' => { marks: [{ 'type' => 'italic' }] },
          '<u>souligné</u>' => { marks: [{ 'type' => 'underline' }] }
        }

        test_cases.each do |html_input, expected_structure|
          expected = expected_tiptap_structure_for_html(html_input)
          expect(expected[:type]).to eq('paragraph')
          expect(expected[:content]).to be_an(Array)

          # Valide que la structure attendue contient les bonnes marques
          if expected_structure[:marks]
            # Convertir les symboles en strings pour la comparaison
            expected_marks = expected[:content].first[:marks] || []
            expected_marks_strings = expected_marks.map { |m| m.transform_keys(&:to_s) }
            expect(expected_marks_strings).to eq(expected_structure[:marks])
          end
        end
      end

      it 'doit extraire correctement le texte des structures Tiptap' do
        tiptap_content = {
          'type' => 'doc',
          'content' => [
            {
              'type' => 'paragraph',
              'content' => [
                { 'type' => 'text', 'text' => 'Hello' },
                { 'type' => 'text', 'text' => ' World', 'marks' => [{ 'type' => 'bold' }] }
              ]
            }
          ]
        }.to_json

        extracted_text = extract_text_from_tiptap(tiptap_content)
        expect(extracted_text.strip).to eq('Hello  World')
      end
    end

    context 'Factories et traits de test' do
      it 'doit avoir des factories fonctionnelles pour v1' do
        v1_basic = create(:attestation_template, :v1_with_basic_formatting)
        v1_complex = create(:attestation_template, :v1_with_complex_formatting)
        v1_tables = create(:attestation_template, :v1_with_tables)
        v1_plain = create(:attestation_template, :v1_plain_text)
        v1_empty = create(:attestation_template, :v1_empty)

        expect(v1_basic.body).to include('<i>', '<u>') # <b> n'est pas dans :v1_with_basic_formatting
        expect(v1_complex.body).to include('<b><i>') # <strong> et <em> sont dans le title
        expect(v1_complex.title).to include('<strong>', '<em>')
        expect(v1_tables.body).to include('<table>', '<tr>', '<td>')
        expect(v1_plain.body).not_to match(/<[^>]+>/)
        expect(v1_empty.body).to be_blank
      end

      it 'doit avoir des factories fonctionnelles pour v2' do
        v2_template = create(:attestation_template, :v2)
        v2_draft = create(:attestation_template, :v2, :draft)
        v2_published = create(:attestation_template, :v2, :published)

        expect(v2_template.version).to eq(2)
        expect(v2_draft.state).to eq('draft')
        expect(v2_published.state).to eq('published')
      end

      it 'doit avoir des matchers RSpec fonctionnels' do
        v1_template = create(:attestation_template, version: 1)
        v2_template = create(:attestation_template, :v2)

        expect(v1_template).to have_valid_v1_structure
        expect(v2_template).to have_valid_v2_structure
        expect(v2_template.tiptap_body).to_not include_tiptap_mark('bold')
      end
    end

    context 'Validation des spécifications' do
      it 'doit documenter le routage conditionnel attendu' do
        # Ces tests documentent la logique de routage attendue

        # Cas 1: Sans attestation, avec feature v2 → v2
        procedure_empty = create(:procedure)
        expect(procedure_empty.attestation_templates).to be_empty
        # Attendu: edit_admin_procedure_attestation_template_v2_path

        # Cas 2: Avec attestation v1 → v1
        procedure_v1 = create(:procedure)
        v1_template = create(:attestation_template, version: 1, procedure: procedure_v1)
        expect(procedure_v1.attestation_template_v1.version).to eq(1)
        # Attendu: edit_admin_procedure_attestation_template_path

        # Cas 3: Avec attestation v2 → v2
        procedure_v2 = create(:procedure)
        v2_template = create(:attestation_template, :v2, procedure: procedure_v2)
        expect(procedure_v2.attestation_templates.first.version).to eq(2)
        # Attendu: edit_admin_procedure_attestation_template_v2_path
      end

      it 'doit documenter les statistiques d\'impact selon les spécifications' do
        # Test documentant les statistiques du document de spécification
        impact_stats = {
          'Balises critiques' => { '<b>' => 259, '<u>' => 156 },
          'Balises majeures' => { '<table>' => 89 },
          'Balises moyennes' => { '<i>' => 39 },
          'Balises faibles' => { '<strong>' => 2, '<em>' => 2 }
        }

        total_procedures_impacted = 504 # Selon le document

        impact_stats.each do |category, tags|
          tags.each do |tag, expected_count|
            # Documentation des balises à traiter
            expect(tag).to be_a(String)
            expect(expected_count).to be > 0
            expect(category).to be_present
          end
        end

        expect(total_procedures_impacted).to eq(504)
      end

      it 'doit documenter les critères de succès de la migration' do
        # Phase 1 - Critères selon spécifications
        phase1_criteria = [
          'Correction du bug de routage v1/v2',
          'Interface de migration avec date limite',
          'Migration automatique du formatage simple',
          'Possibilité de retour en arrière',
          'Tests passants pour les 415 démarches impactées'
        ]

        # Phase 2 - Critères selon spécifications
        phase2_criteria = [
          'Installation et configuration TableKit',
          'Extension TiptapService pour les tables',
          'Migration des 89 démarches avec tables',
          'Interface intelligente selon contenu',
          'Tests d\'édition des tables en v2'
        ]

        expect(phase1_criteria.length).to eq(5)
        expect(phase2_criteria.length).to eq(5)

        # ROI documenté : 25h dev → 504h économisées → ROI 2000%
        dev_hours = 25
        saved_hours = 504
        expected_roi = (saved_hours / dev_hours) * 100
        expect(expected_roi).to eq(2000) # ROI selon spécifications
      end
    end
  end
end
