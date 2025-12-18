# frozen_string_literal: true

class LexpolService
  attr_reader :champ, :dossier, :apilexpol, :user

  # Liste des champs n'envoyant pas de valeur
  EXCLUDED_CHAMP_TYPES = [
    :piece_justificative,
    :titre_identite,
    :header_section,
    :explication
  ].freeze

  def initialize(champ:, dossier:, apilexpol:, user: nil)
    @champ = champ
    @dossier = dossier
    @apilexpol = apilexpol
    @user = user
  end

  def upsert_dossier(force_create: false)
    if force_create || champ.value.blank?
      create_dossier
    else
      update_dossier
    end
  end

  def create_dossier
    nor = apilexpol.create_dossier(model_id, build_variables)
    return nil if nor.blank?

    champ.update!(value: nor)
    refresh_lexpol_data!
    nor
  end

  def update_dossier
    return nil if champ.value.blank?
    apilexpol.update_dossier(champ.value, build_variables)
    refresh_lexpol_data!
    champ.value
  end

  def build_variables
    variables = {}

    # Utilisation des colonnes d'export comme source de vérité pour les variables dossier/usager
    # Cela garantit que Lexpol reçoit les mêmes données enrichies que les exports
    procedure = dossier.procedure

    procedure.dossier_columns_for_export.each do |column|
      value = column_value_for_lexpol(column, dossier)
      variables[self.class.normalize_variable_name(column.label)] = value
    end

    procedure.usager_columns_for_export.each do |column|
      value = column_value_for_lexpol(column, dossier)
      variables[self.class.normalize_variable_name(column.label)] = value
    end

    # Variables spécifiques qui n'existent pas dans les colonnes d'export
    # mais qui étaient présentes dans l'ancien système pour compatibilité
    if procedure.for_individual?
      mandataire_name = [dossier.mandataire_first_name, dossier.mandataire_last_name].compact_blank.join(' ')
      variables['Mandataire'] = mandataire_name if mandataire_name.present?
    end

    last_instructeur_email = dossier.followers_instructeurs.last&.email
    variables['Dossier instruit par'] = last_instructeur_email if last_instructeur_email.present?

    # Alias pour compatibilité avec les anciens modèles Lexpol
    if procedure.for_individual?
      variables['Demandeur nom'] = variables['Nom'] if variables['Nom'].present?
      variables['Demandeur prénom'] = variables['Prénom'] if variables['Prénom'].present?
      variables['Demandeur civilité'] = variables['Civilité'] if variables['Civilité'].present?
    end
    variables['Demandeur email'] = variables['Adresse électronique'] if variables['Adresse électronique'].present?
    variables['Numéro du dossier'] = variables['Nº dossier'] if variables['Nº dossier'].present?
    variables['Dossier déposé le'] = variables['Date de dépôt'] if variables['Date de dépôt'].present?
    variables['Dossier traité le'] = variables['Date de traitement'] if variables['Date de traitement'].present?
    variables['Dossier passé en instruction le'] = variables['Date de passage en instruction'] if variables['Date de passage en instruction'].present?

    excluded_champ_classes = EXCLUDED_CHAMP_TYPES.map { |t| "Champs::#{t.to_s.camelize}Champ".constantize }

    # Variables des champs avec leur formatage spécial
    # pf: Utiliser project_champs pour avoir TOUS les champs de la révision (même non touchés)
    # et éviter les champs orphelins (stable_id supprimé de la révision)
    (dossier.project_champs_public + dossier.project_champs_private)
      .filter { |c| !c.is_a?(Champs::DossierLinkChamp) }
      .reject { |c| excluded_champ_classes.any? { |klass| c.is_a?(klass) } }
      .each do |champ|
        if champ.present?
          # Variable standard
          variables[self.class.normalize_variable_name(champ.libelle)] = LexpolFieldsService.format_lexpol_value(champ)

          # Variable avec format liste pour MultipleDropDownListChamp
          if champ.is_a?(Champs::MultipleDropDownListChamp)
            variables["#{self.class.normalize_variable_name(champ.libelle)} (liste)"] = LexpolFieldsService.format_as_html_list(champ.selected_options)
          end
        end
      end

    # Mapping personnalisé (ancienne méthode, maintenue pour compatibilité)
    LexpolService.user_mapping(champ.type_de_champ).each do |(source_field, target_field)|
      raw_values = LexpolFieldsService.object_field_values(dossier, source_field)
      final_values = raw_values.map { |val| LexpolFieldsService.format_lexpol_value(val) }
      variables[self.class.normalize_variable_name(target_field)] = final_values.compact_blank.join(', ')
    end

    # pf: Enrichissement avec les champs des dossiers liés
    linked_service = LinkedDossierFieldsService.new(dossier, user)
    linked_service.enrich_variables(variables)
  end

  def refresh_lexpol_data!
    return if champ.value.blank?

    dossier_info = apilexpol.get_dossier_infos(champ.value)

    # pf: Mise à jour du statut et lien dossier
    champ.lexpol_status = dossier_info['statut_libelle'] if dossier_info['statut_libelle'].present?
    champ.lexpol_dossier_url = dossier_info['lienDossier'] if dossier_info['lienDossier'].present?

    # pf: Chercher le lien arrêté publié au JOPF (lienLexpol)
    # Le lien est dans l'élément de type "Arrêté"
    # Note: lienBC et lienElement nécessitent une authentification agent, donc inutiles pour l'email usager
    # Une fois présent, ce lien est immuable (publication JOPF définitive)
    arrete_element = dossier_info['elements']&.find { |el| el['typeElement'] == 'Arrêté' }
    if arrete_element && arrete_element['lienLexpol'].present?
      champ.lexpol_arrete_lien = arrete_element['lienLexpol']
    end

    champ.save!
  end

  def model_id
    champ.type_de_champ.options&.[]('lexpol_modele')
  end

  def self.lexpol_variables(lexpol_type_de_champ, procedure)
    # Utilisation des colonnes d'export pour avoir la liste complète des variables disponibles
    column_variables = (
      procedure.dossier_columns_for_export.map(&:label) +
      procedure.usager_columns_for_export.map(&:label)
    )

    excluded_types = EXCLUDED_CHAMP_TYPES.map { |t| TypeDeChamp.type_champs.fetch(t) }

    champ_variables = procedure.draft_revision.types_de_champ
      .reject { |tdc| tdc.type_champ.in?(excluded_types) }
      .flat_map do |tdc|
        base = [tdc.libelle]
        # Ajouter la version (liste) pour les champs à choix multiples
        base << "#{tdc.libelle} (liste)" if tdc.type_champ == 'multiple_drop_down_list'
        base
      end

    custom_variables = user_mapping(lexpol_type_de_champ).map(&:last)

    # Variables spécifiques qui n'existent pas dans les colonnes d'export
    # mais qui étaient disponibles dans l'ancien système
    legacy_variables = ['Mandataire', 'Dossier instruit par']

    (column_variables + champ_variables + custom_variables + legacy_variables).uniq.sort_by(&:downcase)
  end

  def self.normalize_variable_name(name)
    return '' if name.blank?
    name.tr("\u00A0", ' ')
  end

  private

  def column_value_for_lexpol(column, dossier)
    value = column.value(dossier)
    return '' if value.nil?

    LexpolFieldsService.format_lexpol_value(value)
  rescue StandardError => e
    Rails.logger.warn("Lexpol: impossible de récupérer la valeur de '#{column.label}': #{e.message}")
    ''
  end

  def self.user_mapping(lexpol_type_de_champ)
    mapping_raw = lexpol_type_de_champ.lexpol_mapping || ""
    mapping_raw.lines.map(&:strip).compact_blank
      .map { |ligne| ligne.include?('=') ? ligne.split('=').map(&:strip) : [ligne, ligne] }
  end
end
