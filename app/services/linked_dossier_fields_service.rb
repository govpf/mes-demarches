# frozen_string_literal: true

class LinkedDossierFieldsService
  # Mots non-significatifs à filtrer
  STOP_WORDS = %w[de du des la le l d et ou].freeze

  def initialize(dossier, user = nil)
    @dossier = dossier
    @user = user
    @used_suffixes = [] # Pour détecter les collisions
    @suffix_cache = {}
    @visited_dossier_ids = Set.new
  end

  def enrich_variables(base_variables)
    enriched = base_variables.dup
    @visited_dossier_ids.add(@dossier.id)

    # pf: Précharger tous les dossiers liés pour éviter N+1
    linked_ids = linked_dossier_champs.filter_map { |c| c.value.to_i if c.value.to_i > 0 }
    linked_map = accessible_linked_dossiers(linked_ids).index_by(&:id)

    linked_dossier_champs.each do |champ|
      dossier_id = champ.value.to_i
      linked_dossier = linked_map[dossier_id]
      suffix = generate_suffix(champ.libelle)

      # Si pas d'accès, ajouter un message explicite pour l'indiquer à l'instructeur
      unless linked_dossier
        enriched["#{champ.libelle} (#{suffix})"] = "⚠️ Dossier lié non accessible"
        next
      end

      next if @visited_dossier_ids.include?(dossier_id) # Protection cycle

      @visited_dossier_ids.add(dossier_id)
      linked_variables = extract_linked_dossier_variables(linked_dossier)
      merge_with_suffix(enriched, linked_variables, suffix)
    end

    enriched
  end

  def linked_dossiers_info
    linked_ids = linked_dossier_champs.filter_map { |c| c.value.to_i if c.value.to_i > 0 }
    accessible_ids = accessible_linked_dossiers(linked_ids).pluck(:id)

    linked_dossier_champs.map do |champ|
      dossier_id = champ.value.to_i
      {
        libelle: champ.libelle,
        suffixe: generate_suffix(champ.libelle),
        accessible: accessible_ids.include?(dossier_id),
        dossier_id: dossier_id,
      }
    end
  end

  private

  def linked_dossier_champs
    # pf: Filtrer les champs DossierLink parmi les champs publics uniquement
    @dossier.project_champs_public_all.filter { |c| c.is_a?(Champs::DossierLinkChamp) && c.value.present? }
  end

  def accessible_linked_dossiers(ids)
    return Dossier.none if ids.empty?

    # pf: Vérifier les permissions sur les dossiers liés
    if @user&.instructeur
      # Instructeur peut voir les dossiers des procédures auxquelles il est assigné
      Dossier.where(id: ids)
        .joins(:groupe_instructeur)
        .where(groupe_instructeurs: { id: @user.instructeur.groupe_instructeur_ids })
    elsif @user
      # Usager ne voit que ses propres dossiers
      DossierPolicy::Scope.new(@user, Dossier.where(id: ids)).resolve
    else
      # Fallback : tous les dossiers (usage interne sans user)
      Dossier.where(id: ids)
    end
  end

  def extract_linked_dossier_variables(linked_dossier)
    {}.tap do |variables|
      add_metadata(variables, linked_dossier)
      # pf: Utiliser project_champs pour avoir TOUS les champs de la révision (même non touchés)
      # et éviter les champs orphelins (stable_id supprimé de la révision)
      add_champs(variables, linked_dossier.project_champs_public)
      add_champs(variables, linked_dossier.project_champs_private) if linked_dossier.has_annotations?
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
      'Dossier traité le' => dossier.processed_at,
    }.each do |key, value|
      next unless value

      variables[key] = LexpolFieldsService.format_lexpol_value(value)
      # pf: même règle que LexpolService — un datetime expose sa date et son
      # heure séparément, Lexpol ne sachant mettre en forme que la date.
      if value.is_a?(Time) || value.is_a?(DateTime)
        variables["#{key}#{LexpolService::HEURE_SUFFIX}"] = LexpolFieldsService.format_heure(value)
      end
    end
  end

  def add_champs(variables, champs)
    champs.each do |champ|
      next if champ.is_a?(Champs::DossierLinkChamp) # Éviter la récursion

      variables[champ.libelle] = LexpolFieldsService.format_lexpol_value(champ)
      if champ.is_a?(Champs::DatetimeChamp)
        variables["#{champ.libelle}#{LexpolService::HEURE_SUFFIX}"] = LexpolFieldsService.format_heure(champ.value)
      end
    end
  end

  def generate_suffix(libelle, track_collision: true)
    # Si déjà calculé, retourner le même suffixe
    return @suffix_cache[libelle] if @suffix_cache.key?(libelle)

    words = normalize_and_split(libelle)
    filtered = filter_stopwords(words)
    suffix = select_suffix(filtered, track_collision)

    @used_suffixes << suffix if track_collision
    @suffix_cache[libelle] = suffix # Sauvegarder pour la prochaine fois
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
      suffixed_name = "#{field_name} (#{suffix})"
      enriched[suffixed_name] = value
    end
  end
end
