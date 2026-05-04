# frozen_string_literal: true

module Administrateurs
  class AttestationTemplatesController < AdministrateurController
    before_action :retrieve_procedure
    before_action :preload_revisions

    def show
      redirect_to edit_admin_procedure_attestation_template_path(@procedure)
    end

    def edit
      @attestation_template = build_attestation_template
      @attestation_template.validate
    end

    def update
      @attestation_template = @procedure.attestation_templates.v1.first

      if @attestation_template.update(activated_attestation_params)
        flash.notice = "Le modèle de l’attestation a bien été modifié"

        redirect_to edit_admin_procedure_attestation_template_path(@procedure)
      else
        flash.now.alert = "Le modèle de l’attestation contient des erreurs et n'a pas pu être enregistré. Veuiller les corriger"

        render :edit
      end
    end

    def create
      @attestation_template = build_attestation_template(activated_attestation_params)

      if @attestation_template.save
        flash.notice = "Le modèle de l’attestation a bien été enregistré"

        redirect_to edit_admin_procedure_attestation_template_path(@procedure)
      else
        flash.now.alert = @attestation_template.errors.full_messages

        render :edit
      end
    end

    def preview
      attestation_template = build_attestation_template
      @attestation = attestation_template.render_attributes_for({})

      render 'administrateurs/attestation_templates/show', formats: [:pdf], locals: attestation_template.md_version(@procedure)
    end

    def migrate
      v1_template = @procedure.attestation_templates.v1.first

      unless v1_template
        redirect_to edit_admin_procedure_attestation_template_path(@procedure),
                    alert: "Aucune attestation v1 trouvée"
        return
      end

      # Vérifier si une attestation v2 existe déjà
      v2_template = @procedure.attestation_templates.v2.first

      if v2_template
        # Mettre à jour l'attestation v2 existante avec le contenu v1
        update_v2_from_v1(v2_template, v1_template)
        flash.notice = "✅ Attestation v2 mise à jour avec le contenu v1 !"
      else
        # Créer une nouvelle attestation v2
        v2_template = build_v2_from_v1(v1_template)
        unless v2_template.save
          flash.alert = "❌ Erreur lors de la migration : #{v2_template.errors.full_messages.join(', ')}"
          redirect_to edit_admin_procedure_attestation_template_path(@procedure)
          return
        end
        flash.notice = "✅ Attestation migrée vers v2 ! Vous pouvez la modifier ou revenir à v1 si nécessaire."
      end

      redirect_to edit_admin_procedure_attestation_template_v2_path(@procedure)
    end

    private

    def build_attestation_template(attributes = {})
      attestation_template = @procedure.attestation_templates.v1.first || @procedure.attestation_templates.build(version: 1)
      attestation_template.attributes = attributes
      attestation_template
    end

    def activated_attestation_params
      # cache result to avoid multiple uninterlaced computations
      if @activated_attestation_params.nil?
        @activated_attestation_params = params.require(:attestation_template)
          .permit(:title, :body, :footer, :activated, :logo, :signature, :kind)
      end

      @activated_attestation_params
    end

    def update_v2_from_v1(v2_template, v1_template)
      # Conversion HTML basique (sans tables)
      tiptap_content = convert_v1_content_to_tiptap(v1_template)

      # Mettre à jour le template v2 existant avec le contenu v1
      # Ne pas écraser label_logo pour conserver les modifications utilisateur
      v2_template.update!(
        json_body: tiptap_content.deep_stringify_keys,
        activated: v1_template.activated,
        footer: v1_template.footer,
        official_layout: !v1_template.logo.attached? # Désactiver si logo présent en v1
      )

      # Copie des attachments (remplace les existants)
      v2_template.logo.attach(v1_template.logo.blob) if v1_template.logo.attached?
      v2_template.signature.attach(v1_template.signature.blob) if v1_template.signature.attached?
    end

    def build_v2_from_v1(v1_template)
      # Conversion HTML basique (sans tables)
      tiptap_content = convert_v1_content_to_tiptap(v1_template)

      # Selon la spécification : tous les templates migrés sont créés en état draft
      # pour permettre à l'admin de les valider avant publication
      template_state = :draft

      v2_template = @procedure.attestation_templates.build(
        version: 2,
        kind: v1_template.kind,
        json_body: tiptap_content.deep_stringify_keys,
        activated: v1_template.activated,
        footer: v1_template.footer,
        state: template_state,
        label_logo: @procedure.service&.organisme || "",
        official_layout: !v1_template.logo.attached? # Désactiver si logo présent en v1
      )

      # Copie des attachments
      v2_template.logo.attach(v1_template.logo.blob) if v1_template.logo.attached?
      v2_template.signature.attach(v1_template.signature.blob) if v1_template.signature.attached?

      v2_template
    end

    def convert_v1_content_to_tiptap(v1_template)
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
                    "content" => [{ "type" => "text", "text" => @procedure.service&.organisme || "" }],
                  },
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
          # Title (converti depuis v1) - INLINE, pas de paragraphe wrapper
          {
            "type" => "title",
            "attrs" => { "textAlign" => "center" },
            "content" => title_content,
          },
        ] + body_content,
      }
    end

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
            lines = part.split(/\n+/)
            lines.each_with_index do |line, index|
              unless line.strip.empty?
                text_node = { 'type' => 'text', 'text' => line }
                text_node["marks"] = inherited_marks unless inherited_marks.empty?
                result << text_node
              end

              # Ajouter un saut de paragraphe sauf pour la dernière ligne
              if index < lines.length - 1
                result << { 'type' => 'paragraph_break' } # Marqueur spécial
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
      all_types_de_champ = @procedure.active_revision.types_de_champ_public + @procedure.active_revision.types_de_champ_private

      # Chercher un type de champ avec le même libellé (insensible à la casse)
      matching_tdc = all_types_de_champ.find do |tdc|
        tdc.libelle.downcase.strip == field_label.downcase.strip
      end

      return "tdc#{matching_tdc.stable_id}" if matching_tdc

      # Aucun champ trouvé
      nil
    end

    def process_plain_text_with_fields_and_breaks(text)
      # D'abord traiter les doubles retours à la ligne pour séparer les paragraphes
      if text.include?("\n\n")
        paragraphs = text.split(/\n\s*\n/).compact_blank
        result = []

        paragraphs.each do |para_text|
          # Traiter chaque paragraphe pour les tags de champs
          para_content = if para_text.include?('--')
            parse_text_with_field_tags(para_text.strip)
          else
            [{ "type" => "text", "text" => para_text.strip }]
          end

          # Traiter les paragraph_break dans ce paragraphe
          if para_content.any? { |node| node["type"] == "paragraph_break" }
            current_paragraph = []

            para_content.each do |node|
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
          else
            result << { 'type' => 'paragraph', 'content' => para_content }
          end
        end

        return result
      else
        # Traiter le texte avec les tags de champs
        content_nodes = if text.include?('--')
          parse_text_with_field_tags(text)
        else
          [{ 'type' => 'text', 'text' => text }]
        end

        # Traiter les paragraph_break pour créer des paragraphes séparés
        if content_nodes.any? { |node| node["type"] == "paragraph_break" }
          result = []
          current_paragraph = []

          content_nodes.each do |node|
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
        else
          [{ 'type' => 'paragraph', 'content' => content_nodes }]
        end
      end
    end
  end
end
