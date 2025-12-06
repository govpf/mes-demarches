# frozen_string_literal: true

# Helpers pour les tests de migration d'attestations v1→v2
module AttestationMigrationHelpers
  # Créée une attestation v1 avec formatage HTML spécifique
  def create_v1_template_with_html(html_content, **attributes)
    default_attrs = {
      version: 1,
      title: 'Titre test',
      body: html_content,
      footer: 'Footer test',
      activated: true
    }

    create(:attestation_template, default_attrs.merge(attributes))
  end

  # Analyse le contenu HTML d'une attestation v1
  def analyze_v1_html_content(html_string)
    return { has_formatting: false, tags: [], has_tables: false } if html_string.blank?

    {
      has_formatting: html_string.match?(/<[^>]+>/),
      basic_tags: html_string.scan(/<(b|i|u|strong|em)>/).flatten.uniq,
      table_count: html_string.scan(/<table/).length,
      has_tables: html_string.include?('<table'),
      unsupported_tags: html_string.scan(/<(font|color|div|span)>/).flatten.uniq
    }
  end

  # Simule la conversion HTML vers structure Tiptap (pour documentation)
  def expected_tiptap_structure_for_html(html_content)
    # Ceci sert de documentation pour ce qui est attendu
    case html_content
    when '<b>gras</b>'
      {
        type: 'paragraph',
        content: [
          { type: 'text', text: 'gras', marks: [{ type: 'bold' }] }
        ]
      }
    when '<i>italique</i>'
      {
        type: 'paragraph',
        content: [
          { type: 'text', text: 'italique', marks: [{ type: 'italic' }] }
        ]
      }
    when '<u>souligné</u>'
      {
        type: 'paragraph',
        content: [
          { type: 'text', text: 'souligné', marks: [{ type: 'underline' }] }
        ]
      }
    else
      {
        type: 'paragraph',
        content: [
          { type: 'text', text: html_content.gsub(/<[^>]+>/, '') }
        ]
      }
    end
  end

  # Vérifie qu'un template v2 a la structure Tiptap valide
  def has_valid_tiptap_structure?(tiptap_json)
    return false if tiptap_json.blank?

    parsed = JSON.parse(tiptap_json) rescue nil
    return false if parsed.nil?

    parsed['type'] == 'doc' && parsed['content'].is_a?(Array)
  end

  # Extrait le texte brut d'une structure Tiptap
  def extract_text_from_tiptap(tiptap_json)
    return '' if tiptap_json.blank?

    parsed = JSON.parse(tiptap_json) rescue {}
    extract_text_recursive(parsed['content'] || [])
  end

  private

  def extract_text_recursive(content_array)
    content_array.map do |node|
      if node['text']
        node['text']
      elsif node['content']
        extract_text_recursive(node['content'])
      else
        ''
      end
    end.flatten.join(' ')
  end
end

# Matchers RSpec personnalisés pour les tests d'attestations
RSpec::Matchers.define :have_valid_v1_structure do
  match do |attestation_template|
    attestation_template.version == 1 &&
    attestation_template.title.present? &&
    attestation_template.body.present?
  end

  failure_message do |attestation_template|
    "expected #{attestation_template} to have valid v1 structure (version=1, title and body present)"
  end
end

RSpec::Matchers.define :have_valid_v2_structure do
  match do |attestation_template|
    attestation_template.version == 2 &&
    attestation_template.tiptap_body.present? &&
    JSON.parse(attestation_template.tiptap_body)['type'] == 'doc'
  rescue JSON::ParserError
    false
  end

  failure_message do |attestation_template|
    "expected #{attestation_template} to have valid v2 structure (version=2, valid tiptap_body JSON)"
  end
end

RSpec::Matchers.define :include_tiptap_mark do |mark_type|
  match do |tiptap_json|
    parsed = JSON.parse(tiptap_json) rescue {}
    has_mark_recursive?(parsed['content'] || [], mark_type)
  end

  failure_message do |_tiptap_json|
    "expected tiptap JSON to include mark of type #{mark_type}"
  end

  def has_mark_recursive?(content_array, mark_type)
    content_array.any? do |node|
      if node['marks']&.any? { |mark| mark['type'] == mark_type }
        true
      elsif node['content']
        has_mark_recursive?(node['content'], mark_type)
      else
        false
      end
    end
  end
end

RSpec::Matchers.define :include_tiptap_table do
  match do |tiptap_json|
    parsed = JSON.parse(tiptap_json) rescue {}
    has_table_recursive?(parsed['content'] || [])
  end

  failure_message do |_tiptap_json|
    "expected tiptap JSON to include a table structure"
  end

  def has_table_recursive?(content_array)
    content_array.any? do |node|
      if node['type'] == 'table'
        true
      elsif node['content']
        has_table_recursive?(node['content'])
      else
        false
      end
    end
  end
end

# Configuration RSpec
RSpec.configure do |config|
  config.include AttestationMigrationHelpers, type: :integration
  config.include AttestationMigrationHelpers, type: :system
  config.include AttestationMigrationHelpers, type: :controller
  config.include AttestationMigrationHelpers, type: :model
end
