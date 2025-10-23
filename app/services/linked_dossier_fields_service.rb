# frozen_string_literal: true

class LinkedDossierFieldsService
  # Mots non-significatifs à filtrer
  STOP_WORDS = %w[de du des la le l d et ou].freeze

  def initialize(dossier)
    @dossier = dossier
    @used_suffixes = [] # Pour détecter les collisions
  end

  def enrich_variables(base_variables)
    enriched = base_variables.dup

    linked_dossier_champs.each do |dossier_link_champ|
      linked_dossier = find_linked_dossier(dossier_link_champ)
      next unless linked_dossier

      suffix = generate_suffix(dossier_link_champ.libelle)
      linked_variables = extract_linked_dossier_variables(linked_dossier)

      merge_with_suffix(enriched, linked_variables, suffix)
    end

    enriched
  end

  def linked_dossiers_info
    linked_dossier_champs.map do |champ|
      { libelle: champ.libelle, suffixe: generate_suffix(champ.libelle, track_collision: false) }
    end
  end

  private

  def linked_dossier_champs
    @dossier.champs.filter { |c| c.is_a?(Champs::DossierLinkChamp) && c.value.present? }
  end

  def find_linked_dossier(dossier_link_champ)
    dossier_id = dossier_link_champ.value.to_i
    Dossier.find_by(id: dossier_id) if dossier_id > 0
  end

  def extract_linked_dossier_variables(linked_dossier)
    {}.tap do |variables|
      add_metadata(variables, linked_dossier)
      add_public_champs(variables, linked_dossier)
      add_private_annotations(variables, linked_dossier) if linked_dossier.has_annotations?
    end
  end

  def add_metadata(variables, dossier)
    {
      'Date de création' => dossier.created_at,
      'Date de modification' => dossier.updated_at,
      'Numéro du dossier' => dossier.id&.to_s,
      'Statut' => dossier.state && I18n.t("activerecord.attributes.dossier/state.#{dossier.state}"),
      'Dossier déposé le' => dossier.depose_at,
      'Dossier passé en instruction le' => dossier.en_instruction_at,
      'Dossier traité le' => dossier.processed_at
    }.each do |key, value|
      variables[key] = LexpolFieldsService.format_lexpol_value(value) if value
    end
  end

  def add_public_champs(variables, dossier)
    add_champs_to_variables(variables, dossier.champs.filter { |c| !c.child? && c.present? })
  end

  def add_private_annotations(variables, dossier)
    add_champs_to_variables(variables, dossier.filled_champs_private)
  end

  def add_champs_to_variables(variables, champs)
    champs.each do |champ|
      next if champ.is_a?(Champs::DossierLinkChamp) # Éviter la récursion
      variables[champ.libelle] = LexpolFieldsService.format_lexpol_value(champ)
    end
  end

  def generate_suffix(libelle, track_collision: true)
    words = normalize_and_split(libelle)
    filtered = filter_stopwords(words)
    suffix = select_suffix(filtered, track_collision)

    @used_suffixes << suffix if track_collision
    suffix
  end

  def normalize_and_split(libelle)
    libelle
      .gsub(/\([^)]*\)/, '') # Supprimer parenthèses
      .strip
      .split(/\s+/)
      .reject(&:empty?)
      .map { |word| word.gsub(/^[ld]'/i, '') } # Supprimer l' ou d' en début de mot
  end

  def filter_stopwords(words)
    filtered = words.reject { |w| w.downcase.in?(STOP_WORDS) }
    filtered.empty? ? words : filtered # Fallback si tous les mots sont filtrés
  end

  def select_suffix(words, track_collision)
    last_word = words.last
    track_collision && collision_detected?(last_word) ? words.last(2).join(' ') : last_word
  end

  def collision_detected?(suffix)
    @used_suffixes.include?(suffix)
  end

  def merge_with_suffix(enriched, linked_variables, suffix)
    linked_variables.each do |field_name, value|
      suffixed_name = "#{field_name} #{suffix}"
      enriched[suffixed_name] = value
    end
  end
end
