# frozen_string_literal: true

class ChampPresentations::RepetitionPresentation < ChampPresentations::BasePresentation
  attr_reader :libelle
  attr_reader :rows

  def initialize(libelle, rows)
    @libelle = libelle
    @rows = rows
  end

  def to_s
    # pf: toujours utiliser format tableau avec seulement les champs fillables
    to_html_table
  end

  def to_tiptap_node
    # pf: toujours utiliser format tableau avec seulement les champs fillables
    to_table_node
  end

  private

  # pf: génère un nœud tableau avec seulement les champs fillables
  def to_table_node
    fillable_rows = filter_fillable_champs
    return { type: 'paragraph', content: [{ type: 'text', text: 'Aucune donnée' }] } if fillable_rows.empty?

    # En-têtes (seulement les champs fillables de la première ligne)
    headers = fillable_rows.first.map { |champ| champ.type_de_champ.libelle }
    header_cells = headers.map do |header|
      {
        type: 'tableHeader',
        content: [{ type: 'paragraph', content: [{ type: 'text', text: header }] }]
      }
    end

    # Lignes de données (seulement les champs fillables)
    data_rows = fillable_rows.map do |row_champs|
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

  # pf: filtre pour garder seulement les champs fillables dans chaque ligne
  def filter_fillable_champs
    rows.map do |row_champs|
      row_champs.filter { |champ| champ.type_de_champ.fillable? }
    end.reject(&:empty?) # Supprime les lignes vides
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

  # pf: génère HTML tableau simple pour compatibilité v1 (seulement champs fillables)
  def to_html_table
    fillable_rows = filter_fillable_champs
    return '' if fillable_rows.empty?

    # En-têtes (seulement les champs fillables)
    headers = fillable_rows.first.map { |champ| champ.type_de_champ.libelle }
    header_row = "<tr>#{headers.map { |h| "<th>#{h}</th>" }.join}</tr>"

    # Lignes de données (seulement les champs fillables)
    data_rows = fillable_rows.map do |row_champs|
      cells = row_champs.map do |champ|
        cell_value = champ.type_de_champ.champ_value_for_tag(champ)
        cell_content = if cell_value.respond_to?(:to_s)
          cell_value.to_s
        else
          cell_value.to_s
        end
        "<td>#{cell_content}</td>"
      end
      "<tr>#{cells.join}</tr>"
    end

    "<table>#{header_row}#{data_rows.join}</table>"
  end

  # pf: génère HTML liste pour compatibilité v1 (format texte historique)
  def to_html_list
    ([libelle] + rows.map do |champs|
      champs.map do |champ|
        cell_value = champ.type_de_champ.champ_value_for_tag(champ)
        "#{champ.libelle} : #{cell_value}"
      end.join("\n")
    end).join("\n\n")
  end
end
