# frozen_string_literal: true

class ChampPresentations::RepetitionPresentation < ChampPresentations::BasePresentation
  attr_reader :libelle
  attr_reader :rows

  def initialize(libelle, rows)
    @libelle = libelle
    @rows = rows
  end

  def to_s
    ([libelle] + rows.map do |champs|
      champs.map do |champ|
        "#{champ.libelle} : #{champ}"
      end.join("\n")
    end).join("\n\n")
  end

  def to_tiptap_node
    # Récupérer tous les libellés uniques des champs
    headers = rows.first&.map(&:libelle) || []
    
    {
      type: 'table',
      attrs: { class: 'tdc-repetition' },
      content: [
        # En-tête du tableau
        {
          type: 'tableRow',
          content: headers.map do |header|
            {
              type: 'tableHeader',
              content: [
                {
                  type: 'paragraph',
                  content: [
                    {
                      type: 'text',
                      text: header
                    }
                  ]
                }
              ]
            }
          end
        },
        # Lignes de données
        *rows.map do |champs|
          {
            type: 'tableRow',
            content: champs.map do |champ|
              {
                type: 'tableCell',
                content: [
                  {
                    type: 'paragraph',
                    content: [
                      {
                        type: 'text',
                        text: champ.to_s
                      }
                    ]
                  }
                ]
              }
            end
          }
        end
      ]
    }
  end
end
