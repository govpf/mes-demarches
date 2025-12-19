# frozen_string_literal: true

require 'base64'

class TiptapService
  # NOTE: node must be deep symbolized keys
  def self.used_tags_and_libelle_for(node, tags = Set.new)
    case node
    in type: 'mention', attrs: { id:, label: }, **rest
      tags << [id, label]
    in { content:, **rest } if content.is_a?(Array)
      content.each { used_tags_and_libelle_for(_1, tags) }
    in type:, **rest
      # noopmdp_shell
    end

    tags
  end

  def to_html(node, substitutions = {})
    return '' if node.nil?

    children(node[:content], substitutions, 0).gsub('<p></p>', '')
  end

  def to_texts_and_tags(node, substitutions = {})
    return '' if node.nil?

    children_texts_and_tags(node[:content], substitutions)
  end

  private

  def initialize
    @body_started = false
  end

  def children_texts_and_tags(content, substitutions)
    content.map { node_to_texts_and_tags(_1, substitutions) }.join
  end

  def node_to_texts_and_tags(node, substitutions)
    case node
    in type: 'paragraph', content:
      children_texts_and_tags(content, substitutions)
    in type: 'paragraph' # empty paragraph
      ''
    in type: 'text', text:
      text.strip
    in type: 'mention', attrs: { id:, label: }
      if substitutions.present?
        substitutions.fetch(id) { "--#{id}--" }
      else
        "<span class='fr-tag fr-tag--sm'>#{label}</span>"
      end
    end
  end

  def children(content, substitutions, level)
    return "" if content.nil?
    content.map { node_to_html(_1, substitutions, level) }.join
  end

  def node_to_html(node, substitutions, level)
    if level == 0 && !@body_started && node[:type].in?(['paragraph', 'heading']) && node.key?(:content)
      @body_started = true
      body_start_mark = " class=\"body-start\""
    end

    case node
    in type: 'header', content:
      "<header>#{children(content, substitutions, level + 1)}</header>"
    in type: 'footer', content:, **rest
      "<footer#{text_align(rest[:attrs])}>#{children(content, substitutions, level + 1)}</footer>"
    in type: 'headerColumn', content:, **rest
      "<div#{text_align(rest[:attrs])}>#{children(content, substitutions, level + 1)}</div>"
    in type: 'paragraph', content:, **rest
      "<p#{body_start_mark}#{text_align(rest[:attrs])}>#{children(content, substitutions, level + 1)}</p>"
    in type: 'title', content:, **rest
      "<h1#{text_align(rest[:attrs])}>#{children(content, substitutions, level + 1)}</h1>"
    in type: 'body', content:, **rest
      children(content, substitutions, level + 1).to_s
    in type: 'heading', attrs: { level: hlevel, **attrs }, content:
      "<h#{hlevel}#{body_start_mark}#{text_align(attrs)}>#{children(content, substitutions, level + 1)}</h#{hlevel}>"
    in type: 'bulletList', content:
      "<ul>#{children(content, substitutions, level + 1)}</ul>"
    in type: 'orderedList', content:, **rest
      "<ol#{class_list(rest[:attrs])}>#{children(content, substitutions, level + 1)}</ol>"
    in type: 'listItem', content:
      "<li>#{children(content, substitutions, level + 1)}</li>"
    in type: 'descriptionList', content:
      "<dl>#{children(content, substitutions, level + 1)}</dl>"
    in type: 'descriptionTerm', content:, **rest
      "<dt#{class_list(rest[:attrs])}>#{children(content, substitutions, level + 1)}</dt>"
    in type: 'descriptionDetails', content:
      "<dd>#{children(content, substitutions, level + 1)}</dd>"
    in type: 'text', text:, **rest
      if rest[:marks].present?
        apply_marks(text, rest[:marks])
      else
        text
      end
    in type: 'mention', attrs: { id: }, **rest
      text_or_presentation = substitutions.fetch(id) { "--#{id}--" }
      text = if text_or_presentation.respond_to?(:to_tiptap_node)
        handle_presentation_node(text_or_presentation, substitutions, level + 1)
      else
        text_or_presentation
      end

      if rest[:marks].present?
        apply_marks(text, rest[:marks])
      else
        text
      end
    # pf: nouveaux types de nœuds pour attestation v2 - pièces jointes
    in type: 'attachmentImage', attrs:
      src = attrs[:src] # pf: data URI base64 (variant 400x400)
      href = attrs[:href] # pf: URL authentifiée pour téléchargement
      alt = attrs[:alt] || '' # pf: déjà échappé dans PieceJustificativePresentation
      display = attrs[:display]

      # pf: affichage 200px (comme gallery), data URI fonctionne sans authentification
      image_html = "<img src='#{src}' alt='#{alt}' style='max-width: 200px; max-height: 200px; object-fit: contain;' />"
      link_html = "<a href='#{href}' target='_blank' rel='noopener'>#{display}</a>"
      "<figure class='attachment-image'>#{image_html}<figcaption>#{link_html}</figcaption></figure>"
    in type: 'attachmentLink', attrs:, content:
      href = attrs[:href]
      target = attrs[:target] || '_self'
      rel = attrs[:rel] || ''
      content_html = content&.map { |c| node_to_html(c, substitutions, level + 1) }&.join('')
      # pf: échapper les attributs par sécurité
      target_escaped = ERB::Util.html_escape(target)
      rel_escaped = ERB::Util.html_escape(rel)
      "<a href='#{href}' target='#{target_escaped}' rel='#{rel_escaped}'>#{content_html}</a>"
    # pf: nouveaux types de nœuds pour attestation v2 - tableaux
    in type: 'table', content:
      rows_html = content&.map { |row| node_to_html(row, substitutions, level + 1) }&.join('')
      "<table class='repetition-table'>#{rows_html}</table>"
    in type: 'tableRow', content:
      cells_html = content&.map { |cell| node_to_html(cell, substitutions, level + 1) }&.join('')
      "<tr>#{cells_html}</tr>"
    in type: 'tableCell', content:
      cell_content = content&.map { |c| node_to_html(c, substitutions, level + 1) }&.join('')
      "<td>#{cell_content}</td>"
    in type: 'tableHeader', content:
      header_content = content&.map { |c| node_to_html(c, substitutions, level + 1) }&.join('')
      "<th>#{header_content}</th>"
    in { type: type } if ["paragraph", "title", "heading"].include?(type) && !node.key?(:content)
      # noop
    end
  end

  def handle_presentation_node(presentation, substitutions, level)
    node = presentation.to_tiptap_node
    # Ensure symbol keys for pattern matching consistency
    node = node.deep_symbolize_keys if node.is_a?(Hash)
    content = node_to_html(node, substitutions, level)
    if presentation.block_level?
      "</p>#{content}<p>"
    else
      content
    end
  end

  def text_align(attrs)
    if attrs.present? && attrs[:textAlign].present?
      " style=\"text-align: #{attrs[:textAlign]}\""
    else
      ""
    end
  end

  def class_list(attrs)
    if attrs.present? && attrs[:class].present?
      " class=\"#{attrs[:class]}\""
    end
  end

  def apply_marks(text, marks)
    marks.reduce(text) do |text, mark|
      case mark
      in type: 'bold'
        "<strong>#{text}</strong>"
      in type: 'italic'
        "<em>#{text}</em>"
      in type: 'underline'
        "<u>#{text}</u>"
      in type: 'strike'
        "<s>#{text}</s>"
      in type: 'highlight'
        "<mark>#{text}</mark>"
      end
    end
  end
end
