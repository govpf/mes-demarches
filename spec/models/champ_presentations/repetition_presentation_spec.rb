# frozen_string_literal: true

describe ChampPresentations::RepetitionPresentation do
  let(:libelle) { "Langages de programmation" }
  let(:procedure) {
    create(:procedure, types_de_champ_public: [
      {
        type: :repetition,
        children: [
          { type: :text, libelle: "nom" },
          { type: :integer_number, libelle: "stars" }
        ]
      }
    ])
  }

  let(:dossier) { create(:dossier, procedure:) }
  let(:champ_repetition) { dossier.project_champs_public.first }

  before do
    champ_repetition.add_row(updated_by: 'test')
    champ_repetition.add_row(updated_by: 'test')
    row1, row2, row3 = champ_repetition.rows

    nom, stars = row1
    champ_for_update(nom).update(value: "ruby")
    champ_for_update(stars).update(value: 5)

    nom = row2.first
    champ_for_update(nom).update(value: "js")

    nom, stars = row3
    champ_for_update(nom).update(value: "rust")
    champ_for_update(stars).update(value: 4)
  end

  let(:representation) { described_class.new(libelle, champ_repetition.rows) }

  describe '#to_s' do
    # pf: nouveau comportement - retourne HTML tableau avec seulement champs fillables
    it 'returns HTML table with fillable fields only' do
      expect(representation.to_s).to eq(
        '<table><tr><th>nom</th><th>stars</th></tr><tr><td>ruby</td><td>5</td></tr><tr><td>js</td><td></td></tr><tr><td>rust</td><td>4</td></tr></table>'
      )
    end
  end

  describe '#to_tiptap_node' do
    # pf: test adapté pour la nouvelle logique tableau vs liste descriptive
    context 'avec champs fillables (format tableau PF)' do
      it 'génère une structure de tableau' do
        # pf: nouveau format tableau pour champs simples (avec clés symbols)
        expected_node = {
          type: "table",
          content: [
            {
              type: "tableRow",
              content: [
                {
                  type: "tableHeader",
                  content: [{ type: "paragraph", content: [{ type: "text", text: "nom" }] }]
                },
                {
                  type: "tableHeader",
                  content: [{ type: "paragraph", content: [{ type: "text", text: "stars" }] }]
                }
              ]
            },
            {
              type: "tableRow",
              content: [
                {
                  type: "tableCell",
                  content: [{ type: "paragraph", content: [{ type: "text", text: "ruby" }] }]
                },
                {
                  type: "tableCell",
                  content: [{ type: "paragraph", content: [{ type: "text", text: "5" }] }]
                }
              ]
            },
            {
              type: "tableRow",
              content: [
                {
                  type: "tableCell",
                  content: [{ type: "paragraph", content: [{ type: "text", text: "js" }] }]
                },
                {
                  type: "tableCell",
                  content: [{ type: "paragraph", content: [{ type: "text", text: "" }] }]
                }
              ]
            },
            {
              type: "tableRow",
              content: [
                {
                  type: "tableCell",
                  content: [{ type: "paragraph", content: [{ type: "text", text: "rust" }] }]
                },
                {
                  type: "tableCell",
                  content: [{ type: "paragraph", content: [{ type: "text", text: "4" }] }]
                }
              ]
            }
          ]
        }

        expect(representation.to_tiptap_node).to eq(expected_node)
      end
    end

    # pf: test avec champs non-fillables - génère tableau avec seulement champs fillables
    context 'avec champs non-fillables mélangés' do
      let(:procedure_with_headers) {
        create(:procedure, types_de_champ_public: [
          {
            type: :repetition,
            children: [
              { type: :header_section, libelle: "Section info" },
              { type: :text, libelle: "nom" }
            ]
          }
        ])
      }
      let(:dossier_with_headers) { create(:dossier, procedure: procedure_with_headers) }
      let(:champ_with_headers) { dossier_with_headers.project_champs_public.first }
      let(:representation_with_headers) { described_class.new("Test", champ_with_headers.rows) }

      it 'génère tableau avec seulement les champs fillables' do
        result = representation_with_headers.to_tiptap_node
        # pf: toujours tableau maintenant, avec seulement les champs fillables filtrés
        expect(result[:type]).to eq("table")
        # Une seule colonne "nom" (header_section filtré)
        expect(result[:content].first[:content].size).to eq(1)
        expect(result[:content].first[:content].first[:content].first[:content].first[:text]).to eq("nom")
      end
    end

    # pf: test avec tableau vide (aucune ligne)
    context 'avec tableau vide' do
      let(:empty_representation) { described_class.new(libelle, []) }

      it 'retourne un paragraphe vide (ne pas afficher "Aucune donnée")' do
        result = empty_representation.to_tiptap_node
        expect(result).to eq({ type: 'paragraph', content: [] })
      end

      it 'to_s retourne une chaîne vide' do
        expect(empty_representation.to_s).to eq('')
      end
    end

    # pf: test avec pièces jointes (images et documents) dans les tableaux
    context 'avec pièces jointes dans les cellules' do
      let(:procedure_with_files) {
        create(:procedure, types_de_champ_public: [
          {
            type: :repetition,
            children: [
              { type: :text, libelle: "description" },
              { type: :piece_justificative, libelle: "document" }
            ]
          }
        ])
      }
      let(:dossier_with_files) { create(:dossier, procedure: procedure_with_files) }
      let(:champ_with_files) { dossier_with_files.project_champs_public.first }
      let(:representation_with_files) { described_class.new("Documents", champ_with_files.rows) }

      before do
        row = champ_with_files.rows.first
        description_champ, pj_champ = row
        champ_for_update(description_champ).update(value: "Photo de test")
        champ_for_update(pj_champ).piece_justificative_file.attach(
          io: StringIO.new("fake image"),
          filename: "test.png",
          content_type: "image/png",
          metadata: { virus_scan_result: ActiveStorage::VirusScanner::SAFE }
        )
      end

      it 'préserve les nœuds attachmentImage/attachmentLink dans les cellules' do
        result = representation_with_files.to_tiptap_node

        # Vérifier la structure du tableau
        expect(result[:type]).to eq("table")
        expect(result[:content].size).to eq(2) # header + 1 data row

        # Récupérer la cellule avec la pièce jointe (2ème colonne)
        data_row = result[:content][1]
        pj_cell = data_row[:content][1]
        cell_paragraph = pj_cell[:content].first

        # pf: vérifier que le nœud attachmentImage est préservé (pas converti en texte)
        expect(cell_paragraph[:content]).to be_an(Array)
        attachment_node = cell_paragraph[:content].first
        # pf: upstream utilise des clés symbols
        expect(attachment_node[:type]).to eq('attachmentImage')
        expect(attachment_node[:attrs]).to include(:src, :alt, :display)
        # pf: display contient "Télécharger" (pas le nom du fichier)
        expect(attachment_node[:attrs][:display]).to eq('Télécharger')
        # pf: nom du fichier dans alt pour accessibilité
        expect(attachment_node[:attrs][:alt]).to eq('test.png')
      end
    end
  end
end
