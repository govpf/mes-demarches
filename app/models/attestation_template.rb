# frozen_string_literal: true

class AttestationTemplate < ApplicationRecord
  include ActionView::Helpers::NumberHelper
  include TagsSubstitutionConcern

  belongs_to :procedure

  has_one_attached :logo
  has_one_attached :signature

  enum :state, {
    draft: 'draft',
    published: 'published',
  }

  enum :kind, {
    acceptation: 'acceptation',
    refus: 'refus',
  }

  validates :title, tags: true, if: -> { procedure.present? && version == 1 }
  validates :body, tags: true, if: -> { procedure.present? && version == 1 }
  validates :json_body, tags: true, if: -> { procedure.present? && version == 2 }
  validates :footer, length: { maximum: 190 }
  validates :kind, presence: true

  FILE_MAX_SIZE = 1.megabyte
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
                "content" => [{ "type" => "mention", "attrs" => { "id" => "dossier_service_name", "label" => "nom du service" } }],
              },
            ],
          },
          {
            "type" => "headerColumn",
            "content" => [
              {
                "type" => "paragraph",
                "attrs" => { "textAlign" => "left" },
                "content" => [
                  { "text" => "Fait le ", "type" => "text" },
                  { "type" => "mention", "attrs" => { "id" => "dossier_processed_at", "label" => "date de décision" } },
                ],
              },
            ],
          },
        ],
      },
      { "type" => "title", "attrs" => { "textAlign" => "center" }, "content" => [{ "text" => "Titre de l'attestation", "type" => "text" }] },
      {
        "type" => "paragraph",
        "attrs" => { "textAlign" => "left" },
        "content" => [
          {
            "text" => "Vous pouvez éditer ce texte pour personnaliser votre attestation. Pour ajouter du contenu issu du dossier, utilisez les balises situées sous cette zone de saisie.",
            "type" => "text",
          },
        ],
      },
    ],
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
      # pf: 1200px max pour rester ~300 DPI sur les 100x50mm autorisés en mode libre (et 80x50mm en mode charte)
      logo_variant = logo.variant(resize_to_limit: [1200, 1200])
      logo_variant.key.present? ? logo_variant.processed.url : Rails.application.routes.url_helpers.url_for(logo)
    end
  end

  def render_attributes_for(params = {})
    groupe_instructeur = params[:groupe_instructeur]
    groupe_instructeur ||= params[:dossier]&.groupe_instructeur

    base_attributes = {
      created_at: Time.current,
      footer: params.fetch(:footer, footer),
      signature: signature_to_render(groupe_instructeur),
    }

    if version == 2
      render_attributes_for_v2(params, base_attributes)
    else
      render_attributes_for_v1(params, base_attributes)
    end
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
      table_count: table_count,
    }
  end

  # pf: Migration v1 → v2 - Méthodes de conversion HTML vers TipTap
  def html_to_tiptap_basic(html_string)
    parse_html_to_tiptap(html_string, inline: false)
  end

  def html_to_tiptap_inline(html_string)
    parse_html_to_tiptap(html_string, inline: true)
  end

  # pf: génération SVG du QR code pour vérification attestation.
  # Publique : appelée depuis les controllers qui prévisualisent une attestation v2.
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

  private

  def parse_html_to_tiptap(html_string, inline: false)
    return [] if html_string.blank?

    # Si mode inline, traiter comme avant sans découpage de paragraphes
    if inline
      return parse_html_to_tiptap_inline_content(html_string)
    end

    # Découper le texte sur les retours à la ligne pour créer des paragraphes séparés
    paragraphs = html_string.split(/(\r?\n)+/).compact_blank

    result = []
    paragraphs.each do |paragraph_text|
      paragraph_content = parse_paragraph_to_tiptap(paragraph_text.strip)
      if paragraph_content.any?
        result << {
          'type' => 'paragraph',
          'content' => paragraph_content,
        }
      end
    end

    result
  end

  def parse_html_to_tiptap_inline_content(html_string)
    # Si pas de HTML, traiter directement comme texte avec variables
    unless html_string.match?(/<[^>]+>/)
      return parse_text_with_field_tags(html_string)
    end

    # Parser HTML avec Nokogiri pour le contenu inline
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

  def parse_paragraph_to_tiptap(paragraph_text)
    return [] if paragraph_text.blank?

    # Si pas de HTML, traiter directement comme texte avec variables
    unless paragraph_text.match?(/<[^>]+>/)
      return parse_text_with_field_tags(paragraph_text)
    end

    # Parser HTML avec Nokogiri pour ce paragraphe
    doc = Nokogiri::HTML::DocumentFragment.parse(paragraph_text)
    result = []

    # Traiter chaque nœud au niveau racine
    doc.children.each do |node|
      case node.type
      when Nokogiri::XML::Node::TEXT_NODE
        text = node.text
        if text.present?
          # Traiter les variables --Variable-- dans le texte
          if text.include?('--')
            result.concat(parse_text_with_field_tags(text))
          else
            result << { 'type' => 'text', 'text' => text }
          end
        end
      when Nokogiri::XML::Node::ELEMENT_NODE
        converted = convert_html_element_to_tiptap(node)
        result.concat(converted) if converted.is_a?(Array)
        result << converted if converted.is_a?(Hash)
      end
    end

    # Si aucun contenu trouvé, utiliser le texte brut avec variables
    if result.empty? && paragraph_text.present?
      text = doc.text.strip
      if text.present?
        if text.include?('--')
          result.concat(parse_text_with_field_tags(text))
        else
          result << { 'type' => 'text', 'text' => text }
        end
      end
    end

    result
  end

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
      used_tags = TiptapService.used_tags_and_libelle_for(json)
      substitutions = tags_substitutions(used_tags, dossier, escape: false)
      body = tiptap.to_html(json, substitutions)

      attributes.merge(
        body:,
        qrcode: qrcode_dossier_url(dossier, created_at: dossier.encoded_date(:created_at))
      ).merge(base_attributes)
    else
      attributes.merge(
        body: params.fetch(:body) { tiptap.to_html(json) }
      ).merge(base_attributes)
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
    attributes = render_attributes_for(dossier:)
    body = attributes.fetch(:body)
    signature = attributes.fetch(:signature)

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
        signature: signature,
        qrcode_url: qrcode_url,
        qrcode_svg: qrcode_svg,
      }
    )

    WeasyprintService.generate_pdf(html, { procedure_id: procedure.id, dossier_id: dossier.id })
  end

  # pf: Migration v1 → v2 - Construire une attestation v2 à partir d'une v1
  def self.build_v2_from_v1(v1_template, procedure)
    # État du template : draft si procédure publiée, published si procédure brouillon
    template_state = procedure.publiee? ? 'draft' : 'published'

    v2_template = procedure.attestation_templates.build(
      version: 2,
      kind: v1_template.kind,
      tiptap_body: convert_v1_content_to_tiptap(v1_template, procedure).to_json,
      footer: v1_template.footer,
      activated: v1_template.activated,
      state: template_state,
      label_logo: procedure.service&.organisme || "",
      official_layout: !v1_template.logo.attached? # Désactiver si logo présent en v1
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
                # Nom du service
                {
                  "type" => "paragraph",
                  "attrs" => { "textAlign" => "left" },
                  "content" => [{ "type" => "mention", "attrs" => { "id" => "dossier_service_name", "label" => "nom du service" } }],
                },
              ],
            },
            {
              "type" => "headerColumn",
              "content" => [
                {
                  "type" => "paragraph",
                  "attrs" => { "textAlign" => "right" },
                  "content" => [
                    { "text" => "Fait le ", "type" => "text" },
                    { "type" => "mention", "attrs" => { "id" => "dossier_processed_at", "label" => "date de décision" } },
                  ],
                },
              ],
            },
          ],
        },
        # Titre centré avec le contenu converti v1
        {
          "type" => "title",
          "content" => title_content,
        },
        # Corps avec le contenu converti v1
        {
          "type" => "body",
          "content" => body_content,
        },
      ],
    }
  end

  private

  def convert_html_element_to_tiptap(element, inline_mode: false)
    case element.name.downcase
    when 'b', 'strong'
      apply_mark_to_children(element, 'bold')
    when 'i', 'em'
      apply_mark_to_children(element, 'italic')
    when 'u'
      apply_mark_to_children(element, 'underline')
    when 'p'
      # Pour les paragraphes, extraire le contenu sans wrapper
      result = []
      process_element_children(element, result)
      result
    when 'br'
      [{ type: :text, text: "\n" }]
    else
      # Pour les balises non supportées, traiter récursivement le contenu
      result = []
      process_element_children(element, result)
      result
    end
  end

  # Méthode unifiée pour traiter les enfants d'un élément
  def process_element_children(element, result)
    element.children.each do |child|
      case child.type
      when Nokogiri::XML::Node::TEXT_NODE
        text = child.text
        if text.present?
          # Traiter les variables --Variable-- dans le texte
          if text.include?('--')
            result.concat(parse_text_with_field_tags(text))
          else
            # Traiter les retours à la ligne simples dans le texte HTML
            if text.include?("\n")
              lines = text.split(/\n/)
              lines.each_with_index do |line, index|
                result << { 'type' => 'text', 'text' => line } if line.present?
                # Ajouter hardBreak entre les lignes
                if index < lines.length - 1
                  result << { 'type' => 'hardBreak' }
                end
              end
            else
              result << { 'type' => 'text', 'text' => text }
            end
          end
        end
      when Nokogiri::XML::Node::ELEMENT_NODE
        converted = convert_html_element_to_tiptap(child)
        result.concat(converted) if converted.is_a?(Array)
        result << converted if converted.is_a?(Hash)
      end
    end
  end

  # Appliquer un mark (gras, italique, souligné) aux enfants d'un élément
  def apply_mark_to_children(element, mark_type)
    result = []
    process_element_children(element, result)

    # Ajouter le mark à tous les éléments text
    result.each do |item|
      if item['type'] == 'text'
        item['marks'] = (item['marks'] || []) + [{ 'type' => mark_type }]
      end
    end

    result
  end

  def extract_inline_content(element, result)
    # Délégation à la méthode unifiée
    process_element_children(element, result)
  end

  # Conversion des variables --Variable-- en mentions TipTap
  def parse_text_with_field_tags(text, inherited_marks = [])
    result = []

    # Regex pour détecter les tags de champs : --quelque-chose--
    parts = text.split(/(--[^-]+--)/i)

    parts.each do |part|
      next if part.empty?

      if part.match?(/^--[^-]+--$/i)
        # Extraire le nom du champ (enlever les --)
        field_label = part[2..-3].strip

        # Convertir le libellé vers l'ID TipTap v2
        field_id = convert_field_label_to_id(field_label)

        if field_id
          # Créer une mention TipTap v2
          mention_node = { 'type' => 'mention', 'attrs' => { 'id' => field_id, 'label' => field_label } }
          mention_node["marks"] = inherited_marks unless inherited_marks.empty?
          result << mention_node
        else
          # Si pas de mapping trouvé, conserver comme texte
          text_node = { 'type' => 'text', 'text' => part }
          text_node["marks"] = inherited_marks unless inherited_marks.empty?
          result << text_node
        end
      else
        # Gérer les retours à la ligne dans le texte normal
        if part.include?("\n")
          # Séparer par tous les \n (pas seulement \n\n)
          lines = part.split(/\n/)
          lines.each_with_index do |line, index|
            unless line.strip.empty?
              text_node = { 'type' => 'text', 'text' => line }
              text_node["marks"] = inherited_marks unless inherited_marks.empty?
              result << text_node
            end

            # Ajouter un hardBreak TipTap sauf pour la dernière ligne
            if index < lines.length - 1
              result << { 'type' => 'hardBreak' }
            end
          end
        else
          # Texte normal sans retour à la ligne
          unless part.strip.empty?
            text_node = { 'type' => 'text', 'text' => part }
            text_node["marks"] = inherited_marks unless inherited_marks.empty?
            result << text_node
          end
        end
      end
    end

    result.empty? ? [{ 'type' => 'text', 'text' => text }] : result
  end

  def process_final_structure(nodes)
    # Traiter les paragraph_break pour créer des paragraphes séparés (ancienne logique)
    if nodes.any? { |node| node["type"] == "paragraph_break" }
      result = []
      current_paragraph = []

      nodes.each do |node|
        if node["type"] == "paragraph_break"
          # Finaliser le paragraphe actuel s'il a du contenu
          if current_paragraph.any?
            result << { 'type' => 'paragraph', 'content' => current_paragraph }
            current_paragraph = []
          end
        else
          current_paragraph << node
        end
      end

      # Ajouter le dernier paragraphe s'il y a du contenu
      if current_paragraph.any?
        result << { 'type' => 'paragraph', 'content' => current_paragraph }
      end

      result
    elsif nodes.any? { |node| ["text", "mention", "hardBreak"].include?(node["type"]) }
      # Si on a des nodes inline (text/mention/hardBreak), les wrapper dans un paragraphe
      [{ 'type' => 'paragraph', 'content' => nodes }]
    else
      nodes
    end
  end

  def convert_field_label_to_id(field_label)
    # Mapping des libellés v1 vers les IDs v2 TipTap
    system_field_mappings = {
      'nom' => 'individual_last_name',
      'prénom' => 'individual_first_name',
      'civilité' => 'individual_gender',
      'numéro du dossier' => 'dossier_number',
      'date de dépôt' => 'dossier_depose_at',
      'date de passage en instruction' => 'dossier_en_instruction_at',
      'date de décision' => 'dossier_processed_at',
      'date de mise à jour' => 'dossier_last_champ_updated_at',
      'libellé démarche' => 'dossier_procedure_libelle',
      'nom du service' => 'dossier_service_name',
      'motivation' => 'dossier_motivation',
    }

    # D'abord chercher dans les champs système
    system_id = system_field_mappings[field_label.downcase] || system_field_mappings[field_label]
    return system_id if system_id

    # Ensuite chercher dans les champs de formulaire de la procédure
    form_field_id = find_form_field_id(field_label)
    return form_field_id if form_field_id

    # Si aucun mapping trouvé, retourner nil
    nil
  end

  def find_form_field_id(field_label)
    # Chercher dans tous les types de champs de la procédure (publics et privés)
    all_types_de_champ = procedure.draft_revision.types_de_champ_public +
                        procedure.draft_revision.types_de_champ_private

    # Chercher par libellé exact (insensible à la casse)
    matching_tdc = all_types_de_champ.find do |tdc|
      tdc.libelle.casecmp(field_label).zero?
    end

    return "tdc#{matching_tdc.stable_id}" if matching_tdc

    # Aucun champ trouvé
    nil
  end
end
