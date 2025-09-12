# frozen_string_literal: true

class AttestationTemplate < ApplicationRecord
  include ActionView::Helpers::NumberHelper
  include TagsSubstitutionConcern

  belongs_to :procedure, inverse_of: :attestation_template

  has_one_attached :logo
  has_one_attached :signature

  enum state: {
    draft: 'draft',
    published: 'published'
  }

  validates :title, tags: true, if: -> { procedure.present? && version == 1 }
  validates :body, tags: true, if: -> { procedure.present? && version == 1 }
  validates :json_body, tags: true, if: -> { procedure.present? && version == 2 }
  validates :footer, length: { maximum: 190 }

  FILE_MAX_SIZE = 1.megabytes
  validates :logo, content_type: ['image/png', 'image/jpg', 'image/jpeg'], size: { less_than: FILE_MAX_SIZE }
  validates :signature, content_type: ['image/png', 'image/jpg', 'image/jpeg'], size: { less_than: FILE_MAX_SIZE }

  DOSSIER_STATE = Dossier.states.fetch(:accepte)

  scope :v1, -> { where(version: 1) }
  scope :v2, -> { where(version: 2) }

  TIPTAP_BODY_DEFAULT = {
    "type" => "doc",
    "content" => [
      {
        "type" => "header",
        "content" => [
          {
            "type" => "headerColumn",
                      "content" => [
                        {
                          "type" => "paragraph",
                          "attrs" => { "textAlign" => "left" },
                          "content" => [{ "type" => "mention", "attrs" => { "id" => "dossier_service_name", "label" => "nom du service" } }]
                        }
                      ]
          },
          {
            "type" => "headerColumn",
            "content" => [
              {
                "type" => "paragraph",
                          "attrs" => { "textAlign" => "left" },
                          "content" => [
                            { "text" => "Fait le ", "type" => "text" },
                            { "type" => "mention", "attrs" => { "id" => "dossier_processed_at", "label" => "date de décision" } }
                          ]
              }
            ]
          }
        ]
      },
      { "type" => "title", "attrs" => { "textAlign" => "center" }, "content" => [{ "text" => "Titre de l’attestation", "type" => "text" }] },
      {
        "type" => "paragraph",
        "attrs" => { "textAlign" => "left" },
        "content" => [
          {
            "text" => "Vous pouvez éditer ce texte pour personnaliser votre attestation. Pour ajouter du contenu issu du dossier, utilisez les balises situées sous cette zone de saisie.",
            "type" => "text"
          }
        ]
      }
    ]
  }.freeze

  def attestation_for(dossier)
    attestation = Attestation.new
    attestation.title = replace_tags(title, dossier, escape: false) if version == 1
    attestation.pdf.attach(
      io: StringIO.new(build_pdf(dossier)),
      filename: "attestation-dossier-#{dossier.id}.pdf",
      content_type: 'application/pdf',
      # we don't want to run virus scanner on this file
      metadata: { virus_scan_result: ActiveStorage::VirusScanner::SAFE }
    )
    attestation
  end

  def unspecified_champs_for_dossier(dossier)
    types_de_champ_by_tag_id = dossier.revision.types_de_champ.index_by { "tdc#{_1.stable_id}" }

    used_tags.filter_map do |used_tag|
      corresponding_type_de_champ = types_de_champ_by_tag_id[used_tag]

      if corresponding_type_de_champ && dossier.project_champ(corresponding_type_de_champ).blank?
        corresponding_type_de_champ
      end
    end
  end

  def dup
    attestation_template = super
    ClonePiecesJustificativesService.clone_attachments(self, attestation_template)
    attestation_template
  end

  def logo_url
    if logo.attached?
      logo_variant = logo.variant(resize_to_limit: [400, 400])
      logo_variant.key.present? ? logo_variant.processed.url : Rails.application.routes.url_helpers.url_for(logo)
    end
  end

  def signature_url
    if signature.attached?
      Rails.application.routes.url_helpers.url_for(signature)
    end
  end

  def render_attributes_for(params = {})
    groupe_instructeur = params[:groupe_instructeur]
    groupe_instructeur ||= params[:dossier]&.groupe_instructeur

    base_attributes = {
      created_at: Time.current,
      footer: params.fetch(:footer, footer),
      signature: signature_to_render(groupe_instructeur)
    }

    if version == 2
      render_attributes_for_v2(params, base_attributes)
    else
      render_attributes_for_v1(params, base_attributes)
    end
  end

  def logo_checksum
    logo.attached? ? logo.checksum : nil
  end

  def signature_checksum
    signature.attached? ? signature.checksum : nil
  end

  def logo_filename
    logo.attached? ? logo.filename : nil
  end

  def signature_filename
    signature.attached? ? signature.filename : nil
  end

  def md_version(procedure)
    { md_version: procedure.feature_enabled?(:md_attestation_v2) ? :v2 : :v1 }
  end

  def tiptap_body
    json_body&.to_json
  end

  def tiptap_body=(json)
    self.json_body = JSON.parse(json)
  end

  def analyze_v1_content
    content = [title, body].join(' ')
    doc = Nokogiri::HTML::DocumentFragment.parse(content)

    basic_tags = []

    # Détecter les balises de formatage basique
    %w[b i u strong em].each do |tag|
      basic_tags << tag if doc.css(tag).any?
    end

    # Compter les tables
    table_count = doc.css('table').count

    {
      has_basic_formatting: basic_tags.any?,
      has_tables: table_count > 0,
      basic_tags: basic_tags,
      table_count: table_count
    }
  end

  # pf: Migration v1 → v2 - Méthodes de conversion HTML vers TipTap
  def html_to_tiptap_basic(html_string)
    return [] if html_string.blank?

    # Parser HTML avec Nokogiri
    doc = Nokogiri::HTML::DocumentFragment.parse(html_string)

    result = []

    # Traiter chaque nœud au niveau racine
    doc.children.each do |node|
      case node.type
      when Nokogiri::XML::Node::TEXT_NODE
        text = node.text.strip
        result << { 'type' => 'text', 'text' => text } if text.present?
      when Nokogiri::XML::Node::ELEMENT_NODE
        converted = convert_html_element_to_tiptap(node)
        result.concat(converted) if converted.is_a?(Array)
        result << converted if converted.is_a?(Hash)
      end
    end

    # Si aucun contenu trouvé, convertir en texte brut
    if result.empty? && html_string.present?
      text = doc.text.strip
      result << { 'type' => 'text', 'text' => text } if text.present?
    end

    result
  end

  def html_to_tiptap_inline(html_string)
    return [] if html_string.blank?

    # Pour le titre, on veut juste le contenu sans paragraphes
    doc = Nokogiri::HTML::DocumentFragment.parse(html_string)

    result = []
    extract_inline_content(doc, result)

    # Si aucun contenu trouvé, utiliser le texte brut
    if result.empty?
      text = doc.text.strip
      result << { 'type' => 'text', 'text' => text } if text.present?
    end

    result
  end

  private

  def render_attributes_for_v1(params, base_attributes)
    attributes = base_attributes.merge(
      logo: params.fetch(:logo, logo.attached? ? logo : nil)
    )

    dossier = params[:dossier]

    if dossier.present?
      attributes.merge(
        title: replace_tags(title, dossier, escape: false),
        body: replace_tags(body, dossier, escape: false),
        qrcode: dossier.created_at ? qrcode_dossier_url(dossier, created_at: dossier.encoded_date(:created_at)) : nil
      )
    else
      attributes.merge(
        title: params.fetch(:title, title),
        body: params.fetch(:body, body)
      )
    end
  end

  def render_attributes_for_v2(params, base_attributes)
    dossier = params[:dossier]

    json = json_body&.deep_symbolize_keys
    tiptap = TiptapService.new

    if dossier.present?
      # 2x faster this way than with `replace_tags` which would reparse text
      used_tags = TiptapService.used_tags_and_libelle_for(json.deep_symbolize_keys)
      substitutions = tags_substitutions(used_tags, dossier, escape: false)
      body = tiptap.to_html(json, substitutions)

      attributes.merge(
        body:,
        qrcode: qrcode_dossier_url(dossier, created_at: dossier.encoded_date(:created_at))
      )
    else
      attributes.merge(
        body: params.fetch(:body) { tiptap.to_html(json) }
      )
    end
  end

  def signature_to_render(groupe_instructeur)
    if groupe_instructeur&.signature&.attached?
      groupe_instructeur.signature
    else
      signature
    end
  end

  def used_tags
    if version == 2
      json = json_body&.deep_symbolize_keys
      TiptapService.used_tags_and_libelle_for(json.deep_symbolize_keys).map(&:first)
    else
      used_tags_for(title) + used_tags_for(body)
    end
  end

  def build_pdf(dossier)
    if version == 2
      build_v2_pdf(dossier)
    else
      build_v1_pdf(dossier)
    end
  end

  def build_v1_pdf(dossier)
    attestation = render_attributes_for(dossier: dossier)
    ApplicationController.render(
      template: 'administrateurs/attestation_templates/show',
      formats: :pdf,
      assigns: { attestation: attestation },
      locals: md_version(dossier.procedure)
    )
  end

  def build_v2_pdf(dossier)
    body = render_attributes_for(dossier:).fetch(:body)

    # pf: génération QR code comme dans le controller v2s
    qrcode_url = qrcode_dossier_url(dossier, created_at: dossier.encoded_date(:created_at))
    qrcode_svg = qrcode_url ? generate_qrcode_svg(qrcode_url) : nil

    html = ApplicationController.render(
      template: '/administrateurs/attestation_template_v2s/show',
      formats: [:html],
      layout: 'attestation',
      assigns: {
        attestation_template: self,
        body: body,
        qrcode_url: qrcode_url,
        qrcode_svg: qrcode_svg
      }
    )

    WeasyprintService.generate_pdf(html, { procedure_id: procedure.id, dossier_id: dossier.id })
  end

  # pf: génération SVG du QR code pour vérification attestation
  def generate_qrcode_svg(url)
    require 'rqrcode'
    qrcode = RQRCode::QRCode.new(url)
    qrcode.as_svg(
      offset: 0,
      color: '000',
      shape_rendering: 'crispEdges',
      module_size: 3,
      standalone: true
    )
  rescue StandardError
    nil
  end

  # pf: Migration v1 → v2 - Construire une attestation v2 à partir d'une v1
  def self.build_v2_from_v1(v1_template, procedure)
    # État du template : draft si procédure publiée, published si procédure brouillon
    template_state = procedure.publiee? ? 'draft' : 'published'

    v2_template = procedure.attestation_templates.build(
      version: 2,
      tiptap_body: convert_v1_content_to_tiptap(v1_template, procedure).to_json,
      footer: v1_template.footer,
      activated: v1_template.activated,
      state: template_state,
      label_logo: procedure.service&.organisme || ""
    )

    # Copie des attachments
    v2_template.logo.attach(v1_template.logo.blob) if v1_template.logo.attached?
    v2_template.signature.attach(v1_template.signature.blob) if v1_template.signature.attached?

    v2_template
  end

  def self.convert_v1_content_to_tiptap(v1_template, procedure)
    # IMPORTANT : Le titre ne doit PAS être wrappé dans un paragraphe !
    title_content = v1_template.html_to_tiptap_inline(v1_template.title || "Titre de l'attestation")
    body_content = v1_template.html_to_tiptap_basic(v1_template.body || "")

    # Construire la structure avec le header par défaut d'une attestation v2
    {
      "type" => "doc",
      "content" => [
        # Header à deux colonnes (structure par défaut v2 enrichie)
        {
          "type" => "header",
          "content" => [
            {
              "type" => "headerColumn",
              "content" => [
                # Intitulé de l'institution (organisme)
                {
                  "type" => "paragraph",
                  "attrs" => { "textAlign" => "left" },
                  "content" => [{ "type" => "text", "text" => procedure.service&.organisme || "" }]
                },
                # Nom du service
                {
                  "type" => "paragraph",
                  "attrs" => { "textAlign" => "left" },
                  "content" => [{ "type" => "mention", "attrs" => { "id" => "dossier_service_name", "label" => "nom du service" } }]
                }
              ]
            },
            {
              "type" => "headerColumn",
              "content" => [
                {
                  "type" => "paragraph",
                  "attrs" => { "textAlign" => "right" },
                  "content" => [
                    { "text" => "Fait le ", "type" => "text" },
                    { "type" => "mention", "attrs" => { "id" => "dossier_processed_at", "label" => "date de décision" } }
                  ]
                }
              ]
            }
          ]
        },
        # Titre centré avec le contenu converti v1
        {
          "type" => "title",
          "content" => title_content
        },
        # Corps avec le contenu converti v1
        {
          "type" => "body",
          "content" => body_content
        }
      ]
    }
  end

  private

  def convert_html_element_to_tiptap(element)
    case element.name.downcase
    when 'b', 'strong'
      convert_with_mark(element, 'bold')
    when 'i', 'em'
      convert_with_mark(element, 'italic')
    when 'u'
      convert_with_mark(element, 'underline')
    when 'p'
      # Pour les paragraphes, extraire le contenu sans wrapper
      result = []
      extract_inline_content(element, result)
      result
    when 'br'
      [{ 'type' => 'text', 'text' => "\n" }]
    else
      # Pour les balises non supportées, extraire le texte brut
      text = element.text.strip
      text.present? ? [{ 'type' => 'text', 'text' => text }] : []
    end
  end

  def convert_with_mark(element, mark_type)
    result = []
    element.children.each do |child|
      case child.type
      when Nokogiri::XML::Node::TEXT_NODE
        text = child.text
        if text.present?
          result << { 'type' => 'text', 'text' => text, 'marks' => [{ 'type' => mark_type }] }
        end
      when Nokogiri::XML::Node::ELEMENT_NODE
        # Gérer les balises imbriquées
        nested_result = convert_html_element_to_tiptap(child)
        if nested_result.is_a?(Array)
          nested_result.each do |item|
            if item['marks']
              item['marks'] << { 'type' => mark_type }
            else
              item['marks'] = [{ 'type' => mark_type }]
            end
          end
          result.concat(nested_result)
        end
      end
    end
    result
  end

  def extract_inline_content(element, result)
    element.children.each do |child|
      case child.type
      when Nokogiri::XML::Node::TEXT_NODE
        text = child.text.strip
        result << { 'type' => 'text', 'text' => text } if text.present?
      when Nokogiri::XML::Node::ELEMENT_NODE
        case child.name.downcase
        when 'b', 'strong'
          text = child.text.strip
          if text.present?
            result << { 'type' => 'text', 'text' => text, 'marks' => [{ 'type' => 'bold' }] }
          end
        when 'i', 'em'
          text = child.text.strip
          if text.present?
            result << { 'type' => 'text', 'text' => text, 'marks' => [{ 'type' => 'italic' }] }
          end
        when 'u'
          text = child.text.strip
          if text.present?
            result << { 'type' => 'text', 'text' => text, 'marks' => [{ 'type' => 'underline' }] }
          end
        else
          # Continuer l'extraction pour les autres balises
          extract_inline_content(child, result)
        end
      end
    end
  end
end
