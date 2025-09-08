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
        cell_value = champ.type_de_champ.champ_value_for_tag(champ)
        "#{champ.libelle} : #{cell_value}"
      end.join("\n")
    end).join("\n\n")
  end

  def to_tiptap_node
    # pf: utiliser format tableau pour les répétitions simples
    if use_table_format?
      to_table_node
    else
      to_list_node # Format par défaut
    end
  end

  private

  # pf: détermine si on utilise le format tableau
  def use_table_format?
    return false if rows.empty?
    # Utilise le format tableau si tous les champs de la première ligne sont fillables (pas header/explication)
    rows.first.all? { |champ| champ.type_de_champ.fillable? }
  end

  # pf: génère un nœud tableau
  def to_table_node
    return { type: 'paragraph', content: [{ type: 'text', text: 'Aucune donnée' }] } if rows.empty?

    # En-têtes
    headers = rows.first.map { |champ| champ.type_de_champ.libelle }
    header_cells = headers.map do |header|
      {
        type: 'tableHeader',
        content: [{ type: 'paragraph', content: [{ type: 'text', text: header }] }]
      }
    end

    # Lignes de données
    data_rows = rows.map do |row_champs|
      cells = row_champs.map do |champ|
        cell_content = champ.type_de_champ.champ_value_for_tag(champ)

        # Si c'est un objet Presentation, utiliser to_tiptap_node pour le contenu de la cellule
        if cell_content.respond_to?(:to_tiptap_node)
          node = cell_content.to_tiptap_node
          # Adapter le noeud pour qu'il soit inline dans la cellule
          cell_node_content = if node[:type] == 'paragraph'
            node[:content] || [{ type: 'text', text: cell_content.to_s }]
          else
            [{ type: 'text', text: cell_content.to_s }]
          end
        else
          # Texte simple
          cell_node_content = [{ type: 'text', text: cell_content.to_s }]
        end

        {
          type: 'tableCell',
          content: [{ type: 'paragraph', content: cell_node_content }]
        }
      end
      { type: 'tableRow', content: cells }
    end

    {
      type: 'table',
      content: [
        { type: 'tableRow', content: header_cells },
        *data_rows
      ]
    }
  end

  # pf: génère le format liste original
  def to_list_node
    {
      type: 'orderedList',
      attrs: { class: 'tdc-repetition' },
      content: rows.map do |champs|
        {
          type: 'listItem',
          content: [
            {
              type: 'descriptionList',
              content: champs.map do |champ|
                [
                  {
                    type: 'descriptionTerm',
                    attrs: champ.blank? ? { class: 'invisible' } : nil, # still render libelle so width & alignment are preserved
                    content: [
                      {
                        type: 'text',
                        text: champ.libelle
                      }
                    ]
                  }.compact,
                  {
                    type: 'descriptionDetails',
                    content: [
                      {
                        type: 'text',
                        text: champ.to_s
                      }
                    ]
                  }
                ]
              end.flatten
            }
          ]
        }
      end
    }
  end
end
