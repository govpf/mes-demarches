# frozen_string_literal: true

class TypesDeChampEditor::ChampComponent < ApplicationComponent
  attr_reader :coordinate, :upper_coordinates, :errors

  def initialize(coordinate:, upper_coordinates:, focused: false, errors: '')
    @coordinate = coordinate
    @focused = focused
    @upper_coordinates = upper_coordinates
    @errors = errors
  end

  def referentiel_max_size
    Administrateurs::TypesDeChampController::CSV_MAX_SIZE
  end

  def referentiel_max_lines
    Administrateurs::TypesDeChampController::CSV_MAX_LINES
  end

  def template_detail
    "#{file_extension} – #{file_size}"
  end

  def file_extension
    File.extname(template_file).upcase.delete_prefix(".")
  end

  def file_size
    file_size = Rails.public_path.join(template_file).size
    number_to_human_size(file_size)
  end

  def template_file
    'csv/modele-import-referentiel.csv'
  end

  def filtered_upper_tdcs
    @upper_coordinates.map(&:type_de_champ).filter { |tdc| tdc.private? == type_de_champ.private? }
  end

  # pf: Generate available columns for formula editor
  def available_columns_for_formula
    return [] unless type_de_champ.formule?

    # Optimize: create hash map to avoid N+1 queries
    @types_de_champ_by_stable_id ||= revision.types_de_champ.index_by(&:stable_id)

    own_parent_sid = coordinate.parent_type_de_champ&.stable_id

    base = coordinate.available_columns_for_formula.filter_map do |col|
      # pf: pour une formule HORS d'un bloc, on retire les sous-champs-ligne des
      # répétitions (label "Bloc – Sous-champ", réf {tdc<sub_id>}) : ils ne sont
      # référençables qu'au sein de leur propre ligne. Hors bloc, c'est la forme
      # agrégat "Bloc/Sous-champ" (cf. repetition_aggregate_columns) qui doit être
      # proposée. On garde les siblings quand la formule est DANS le même bloc.
      if col.is_a?(Columns::ChampColumn) && col.stable_id.present?
        col_tdc = @types_de_champ_by_stable_id[col.stable_id]
        parent = col_tdc && revision.parent_of(col_tdc)
        next if parent&.repetition? && parent.stable_id != own_parent_sid
      end

      {
        id: encode_column_id(col),
        label: col.label,
        type: col.type.to_s,
        category: col.table,
        paths: extract_sub_paths(col),
      }.compact
    end

    # pf: entrées bloc-agrégat — un bloc répétable placé AVANT la formule peut
    # être agrégé : NB({Bloc}) ou SOMME({Bloc/Sous-champ}). On expose le bloc
    # comme colonne (label = libellé du bloc → {tdc<bloc>}) avec un `path` par
    # sous-champ (label composite "Bloc/Sous-champ" → {tdc<bloc>/sub_<id>}). Le
    # JS convertToColumnIds mappe ces labels sans modification (cf.
    # formula_editor_controller.ts).
    base + repetition_aggregate_columns
  end

  # pf: blocs répétables agrégables (placés avant la formule) + leurs sous-champs.
  def repetition_aggregate_columns
    reference_position = coordinate.parent&.position || coordinate.position
    own_parent_sid = coordinate.parent_type_de_champ&.stable_id

    revision.types_de_champ.filter_map do |tdc|
      next unless tdc.repetition?
      next if tdc.stable_id == own_parent_sid

      bloc_coordinate = revision.coordinate_for(tdc)
      next if bloc_coordinate.nil? || bloc_coordinate.position >= reference_position

      sub_paths = revision.children_of(tdc).filter(&:fillable?).map do |sub|
        { path: "sub_#{sub.stable_id}", label: "#{tdc.libelle}/#{sub.libelle}" }
      end

      {
        id: "tdc#{tdc.stable_id}",
        label: tdc.libelle,
        type: 'repetition',
        paths: sub_paths,
      }
    end
  end

  def encode_column_id(column)
    # Encode column according to attestation v2 pattern
    if column.is_a?(Columns::ChampColumn) && column.stable_id.present?
      tdc = @types_de_champ_by_stable_id[column.stable_id]
      return nil unless tdc

      type_de_champ.encode_column_id(column, tdc)
    elsif column.is_a?(Columns::DossierColumn)
      # Map dossier column to semantic tag
      case [column.table, column.column.to_s]
      when ['self', 'id']
        'dossier_number'
      when ['self', 'state']
        'dossier_state'
      when ['self', 'depose_at']
        'dossier_depose_at'
      when ['self', 'en_instruction_at']
        'dossier_en_instruction_at'
      when ['self', 'processed_at']
        'dossier_processed_at'
      when ['individual', 'gender']
        'individual_gender'
      when ['individual', 'prenom']
        'individual_first_name'
      when ['individual', 'nom']
        'individual_last_name'
      when ['etablissement', 'entreprise_siren']
        'entreprise_siren'
      when ['etablissement', 'siret']
        'entreprise_siret'
      when ['etablissement', 'entreprise_raison_sociale']
        'entreprise_raison_sociale'
      else
        "#{column.table}_#{column.column}"
      end
    else
      nil
    end
  end

  # pf: Génère la documentation textuelle à copier dans une IA externe
  # pour aider à la rédaction d'une formule. Délègue au service dédié.
  def ai_prompt_for_formula
    return nil unless type_de_champ.formule?

    FormulaAiPromptService.new(
      type_de_champ: type_de_champ,
      coordinate: coordinate
    ).generate
  end

  def extract_sub_paths(column)
    # Return sub-properties for DN, referentiels, etc.
    return nil unless column.is_a?(Columns::ChampColumn) && column.stable_id.present?

    tdc = @types_de_champ_by_stable_id[column.stable_id]
    return nil unless tdc

    # Get paths from the type_de_champ
    paths = case tdc.type_champ
    when 'numero_dn'
      [{ path: 'date_de_naissance', label: 'Date de naissance' }]
    when 'code_postal_polynesie'
      [
        { path: 'commune', label: 'Commune' },
        { path: 'ile', label: 'Île' },
        { path: 'archipel', label: 'Archipel' },
      ]
    when 'referentiel_de_polynesie'
      # Get columns from referentiel if it exists
      if tdc.referentiel&.headers.present?
        tdc.referentiel.headers.map { |header| { path: header, label: header } }
      else
        nil
      end
    when 'siret', 'rna'
      # SIRET/RNA have predefined sub-paths
      [
        { path: 'code_naf', label: 'Code NAF' },
        { path: 'raison_sociale', label: 'Raison sociale' },
        { path: 'adresse', label: 'Adresse' },
      ]
    else
      nil
    end

    paths
  end

  private

  delegate :type_de_champ, :revision, :procedure, to: :coordinate

  def can_be_mandatory?
    # pf: Un champ formule est calculé par le système, jamais saisi par
    # l'usager — la notion d'obligatoire n'a pas de sens. C'est à la SOURCE
    # référencée d'être marquée obligatoire si nécessaire.
    type_de_champ.public? && !type_de_champ.non_fillable? && !type_de_champ.formule?
  end

  def type_de_champ_path
    admin_procedure_type_de_champ_path(procedure, type_de_champ.stable_id)
  end

  def html_options
    {
      id: dom_id(coordinate, :type_de_champ_editor),
      class: class_names('type-header-section': type_de_champ.header_section?,
        first: coordinate.first?,
        last: coordinate.last?),
      data: {
        controller: 'type-de-champ-editor',
        type_de_champ_editor_move_up_url_value: move_up_admin_procedure_type_de_champ_path(procedure, type_de_champ.stable_id),
        type_de_champ_editor_move_down_url_value: move_down_admin_procedure_type_de_champ_path(procedure, type_de_champ.stable_id),
      },
    }
  end

  def form_options
    {
      url: admin_procedure_type_de_champ_path(procedure, type_de_champ.stable_id),
      html: { multipart: true, id: nil, class: 'form width-100' },
    }
  end

  def move_button_options(direction)
    {
      type: 'button',
      data: { action: 'type-de-champ-editor#onMoveButtonClick', type_de_champ_editor_direction_param: direction },
      title: direction == :up ? 'Déplacer le champ vers le haut' : 'Déplacer le champ vers le bas',
    }
  end

  def input_autofocus
    @focused ? { controller: 'autofocus' } : nil
  end

  def types_of_type_de_champ
    cat_scope = "activerecord.attributes.type_de_champ.categorie"
    tdc_scope = "activerecord.attributes.type_de_champ.type_champs"
    TypeDeChamp.type_champs.keys
      .filter(&method(:filter_type_champ))
      .filter(&method(:filter_featured_type_champ))
      .filter(&method(:filter_block_type_champ))
      .filter(&method(:filter_public_or_private_only_type_champ))
      .group_by { TypeDeChamp::TYPE_DE_CHAMP_TO_CATEGORIE.fetch(_1.to_sym) }
      .sort_by { |k, _v| TypeDeChamp::CATEGORIES.find_index(k) }
      .to_h do |cat, tdc|
        [
          t(cat, scope: cat_scope),
          tdc.map { [t(_1, scope: tdc_scope), _1, { disabled: !accepted_type_champs.include?(_1) }] },
        ]
      end
  end

  ACCEPTED_TYPES = Columns::ChampColumn::CAST.keys
    .group_by { |(from)| from.to_s }
    .transform_values { |pairs| pairs.map { |(_, to)| to.to_s } }

  def accepted_type_champs
    @accepted_type_champs ||= if published_type_champ.present?
      ([published_type_champ] + ACCEPTED_TYPES.fetch(published_type_champ, [])).uniq
    else
      TypeDeChamp.type_champs.keys
    end
  end

  def published_type_champ
    @published_type_champ ||= procedure.published_revision&.types_de_champ&.find { _1.stable_id == type_de_champ.stable_id }&.type_champ
  end

  def disabled_type_de_champ_select?
    coordinate.used_by_routing_rules? || coordinate.used_by_ineligibilite_rules? || accepted_type_champs.size == 1
  end

  def piece_justificative_template_options
    {
      attached_file: type_de_champ.piece_justificative_template,
      auto_attach_url: helpers.auto_attach_url(type_de_champ, procedure_id: procedure.id),
      view_as: :download,
    }
  end

  def notice_explicative_options
    {
      attached_file: type_de_champ.notice_explicative,
      auto_attach_url: helpers.auto_attach_url(type_de_champ, procedure_id: procedure.id),
      view_as: :download,
    }
  end

  EXCLUDE_FROM_BLOCK = [
    TypeDeChamp.type_champs.fetch(:repetition),
  ]

  def filter_block_type_champ(type_champ)
    !coordinate.child? || !EXCLUDE_FROM_BLOCK.include?(type_champ)
  end

  def filter_public_or_private_only_type_champ(type_champ)
    if coordinate.private?
      true
    else
      !TypeDeChamp::PRIVATE_ONLY_TYPES.include?(type_champ)
    end
  end

  def filter_featured_type_champ(type_champ)
    feature_name = TypeDeChamp::FEATURE_FLAGS[type_champ.to_sym]
    feature_name.blank? || procedure.feature_enabled?(feature_name)
  end

  def filter_type_champ(type_champ)
    if type_champ == TypeDeChamp.type_champs.fetch(:titre_identite)
      return type_de_champ.titre_identite?
    end

    case type_champ
    when TypeDeChamp.type_champs.fetch(:number)
      has_legacy_number?
    when TypeDeChamp.type_champs.fetch(:cnaf)
      procedure.cnaf_enabled?
    when TypeDeChamp.type_champs.fetch(:dgfip)
      procedure.dgfip_enabled?
    when TypeDeChamp.type_champs.fetch(:pole_emploi)
      procedure.pole_emploi_enabled?
    when TypeDeChamp.type_champs.fetch(:mesri)
      procedure.mesri_enabled?
    else
      true
    end
  end

  def format_families_for_select
    return [] if !defined?(FORMAT_FAMILIES)

    FORMAT_FAMILIES.keys.map do |key|
      [
        key,
        I18n.t("activerecord.attributes.type_de_champ.format_families.#{key}", default: key.to_s.humanize),
        (defined?(FORMAT_FAMILY_EXAMPLES) && FORMAT_FAMILY_EXAMPLES[key]),
      ]
    end
  end

  def has_legacy_number?
    revision.types_de_champ.any?(&:number?)
  end

  def lexpol_models
    service_siret = coordinate.procedure&.service&.siret
    return [] if service_siret.blank?

    # Pour la configuration : seuls les super admins utilisent les comptes de test
    use_test_user = current_super_admin.present?
    email = current_super_admin&.email || current_user.email

    cache_key = "lexpol_models:#{service_siret}:#{use_test_user}"
    Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
      begin
        APILexpol.new(email, service_siret, use_test_user).get_models
      rescue APILexpol::LexpolAccessDenied => e
        # pf: Stocker l'erreur d'accès pour affichage différencié dans le template
        Rails.logger.error "Lexpol: Accès refusé pour #{e.email_used}"
        @lexpol_error = { type: :access_denied, email: e.email_used }
        []
      rescue => e
        # pf: Autres erreurs (réseau, parsing, etc.)
        Rails.logger.error "Erreur lors de la récupération des modèles Lexpol: #{e.message}"
        @lexpol_error = { type: :generic, message: e.message }
        []
      end
    end
  end

  # pf: Permet au template d'afficher un message d'erreur adapté
  def lexpol_error
    @lexpol_error
  end

  def lexpol_service_configured?
    coordinate.procedure&.service&.siret.present?
  end

  def options_for_character_limit
    [
      [t('.character_limit.unlimited'), nil],
      [t('.character_limit.limit', limit: '400'), 400],
      [t('.character_limit.limit', limit: '1 000'), 1000],
      [t('.character_limit.limit', limit: '5 000'), 5000],
      [t('.character_limit.limit', limit: '10 000'), 10000],
    ]
  end

  def turbo_confirm
    if coordinate.prefilled_by_type_de_champ
      "Vous avez configuré un pré remplissage de ce champ à partir des données du référentiel du champ « #{coordinate.prefilled_by_type_de_champ.libelle} ». Voulez-vous vraiment le supprimer ?"
    else
      'Êtes vous sûr de vouloir supprimer ce champ ?'
    end
  end
end
