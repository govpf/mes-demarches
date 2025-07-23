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
  let(:champ_repetition) { dossier.champs.find(&:repetition?) }

  before do
    champ_repetition.add_row(updated_by: 'test')
    champ_repetition.add_row(updated_by: 'test')
    row1, row2, row3 = champ_repetition.rows

    nom, stars = row1
    nom.update(value: "ruby")
    stars.update(value: 5)

    nom = row2.first
    nom.update(value: "js")

    nom, stars = row3
    nom.update(value: "rust")
    stars.update(value: 4)
  end

  let(:representation) { described_class.new(libelle, champ_repetition.rows) }

  describe '#to_s' do
    it 'returns a key-value representation' do
      expect(representation.to_s).to eq(
        <<~TXT.strip
          Langages de programmation

          nom : ruby
          stars : 5

          nom : js
          stars :#{' '}

          nom : rust
          stars : 4
        TXT
      )
    end
  end

  describe '#to_tiptap_node' do
    it 'returns the correct table structure' do
      expected_node = {
        type: "table",
        attrs: { class: "tdc-repetition" },
        content: [
          {
            type: "tableRow",
            content: [
              {
                type: "tableHeader",
                content: [
                  {
                    type: "paragraph",
                    content: [{ text: "nom", type: "text" }]
                  }
                ]
              },
              {
                type: "tableHeader",
                content: [
                  {
                    type: "paragraph",
                    content: [{ text: "stars", type: "text" }]
                  }
                ]
              }
            ]
          },
          {
            type: "tableRow",
            content: [
              {
                type: "tableCell",
                content: [
                  {
                    type: "paragraph",
                    content: [{ text: "ruby", type: "text" }]
                  }
                ]
              },
              {
                type: "tableCell",
                content: [
                  {
                    type: "paragraph",
                    content: [{ text: "5", type: "text" }]
                  }
                ]
              }
            ]
          },
          {
            type: "tableRow",
            content: [
              {
                type: "tableCell",
                content: [
                  {
                    type: "paragraph",
                    content: [{ text: "js", type: "text" }]
                  }
                ]
              },
              {
                type: "tableCell",
                content: [
                  {
                    type: "paragraph",
                    content: [{ text: "", type: "text" }]
                  }
                ]
              }
            ]
          },
          {
            type: "tableRow",
            content: [
              {
                type: "tableCell",
                content: [
                  {
                    type: "paragraph",
                    content: [{ text: "rust", type: "text" }]
                  }
                ]
              },
              {
                type: "tableCell",
                content: [
                  {
                    type: "paragraph",
                    content: [{ text: "4", type: "text" }]
                  }
                ]
              }
            ]
          }
        ]
      }

      expect(representation.to_tiptap_node).to eq(expected_node)
    end
  end
end
