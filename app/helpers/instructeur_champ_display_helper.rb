# frozen_string_literal: true

# pf: helper centralisé pour la largeur d'affichage des champs côté instructeur.
# Concentré ici pour éviter d'override display_width dans chaque dynamic_type
# (minimise la divergence upstream sur app/models/types_de_champ/*).
module InstructeurChampDisplayHelper
  LAYOUT_MODES = [:grid, :stacked].freeze
  FEATURE_FLAG = :dossier_layout_grid

  # TODO(rollout): ajuster FEATURE_ROLLOUT_DATE à la date de prod réelle.
  FEATURE_ROLLOUT_DATE = Date.new(2026, 6, 1)
  BANNER_DURATION = 30.days
  DISMISSED_COOKIE = :md_instructeur_dossier_layout_banner_dismissed_at

  TYPE_CHAMP_TO_DISPLAY_WIDTH = {
    # full : champs structurels ou contenu long/visuel
    header_section: :full,
    explication: :full,
    textarea: :full,
    repetition: :full,
    carte: :full,
    dossier_link: :full,
    referentiel_de_polynesie: :full,
    te_fenua: :full,
    engagement_juridique: :full,
    titre_identite: :full,
    # full : siret rend un layout vertical riche (IdentiteEntrepriseComponent et
    # ses variantes : dénomination, numéro Tahiti, forme juridique, adresse...).
    # En attendant une refonte en grid, on l'isole sur sa propre ligne pour ne
    # pas créer de déséquilibre vertical avec des champs courts adjacents.
    siret: :full,
    # half : contenu de taille moyenne
    iban: :half,
    address: :half,
    multiple_drop_down_list: :half,
    # default = :third pour tout le reste
    # piece_justificative et titre_identite : largeur calculée au runtime selon le nombre de fichiers
  }.freeze

  # pf: 95% des champs PJ ne contiennent qu'un seul fichier (mesure prod 2026-04).
  # Pour ce cas dominant, on préfère 1/3 (3 par rangée, thumbnail 200px confortable).
  # À partir de 2 fichiers, on bascule en pleine largeur pour laisser respirer la galerie.
  def champ_display_width(champ)
    if pj_attachment_champ?(champ)
      pj_mono_file?(champ) ? :third : :full
    else
      TYPE_CHAMP_TO_DISPLAY_WIDTH.fetch(champ.type_champ.to_sym, :third)
    end
  end

  def champ_display_width_class(champ)
    "champ-grid-item--#{champ_display_width(champ)}"
  end

  # pf: une PJ mono-fichier (largeur 1/3) doit former une rangée homogène avec ses voisines
  # PJ-mono pour ne pas se mélanger à des champs courts qui décaleraient sa hauteur.
  # → break-before quand on bascule entre "PJ-mono" et "non-PJ-mono".
  # Les PJ multi-fichiers passent en :full et cassent la rangée nativement, donc traitées
  # comme non-PJ-mono dans cette règle.
  def champ_break_before_class(champ, previous_champ)
    return nil if previous_champ.nil?
    return nil if pj_mono_for_grouping?(champ) == pj_mono_for_grouping?(previous_champ)

    'champ-grid-item--break-before'
  end

  def pj_attachment_champ?(champ)
    champ.piece_justificative? || champ.titre_identite?
  end

  def pj_mono_file?(champ)
    champ.piece_justificative_file.attachments.size <= 1
  end

  def pj_mono_for_grouping?(champ)
    pj_attachment_champ?(champ) && pj_mono_file?(champ)
  end

  def instructeur_champs_layout_mode(instructeur = nil)
    value = instructeur&.dossier_layout_preference&.to_sym
    LAYOUT_MODES.include?(value) ? value : :grid
  end

  def instructeur_champs_layout_chosen?(instructeur = nil)
    instructeur&.dossier_layout_preference.present?
  end

  def dossier_layout_grid_enabled?(instructeur)
    instructeur&.feature_enabled?(FEATURE_FLAG)
  end

  def dossier_layout_banner_dismissed?
    cookies[DISMISSED_COOKIE].present?
  end

  def show_dossier_layout_banner?(instructeur)
    return false unless dossier_layout_grid_enabled?(instructeur)
    return false if instructeur_champs_layout_chosen?(instructeur) || dossier_layout_banner_dismissed?

    user_created_at = instructeur&.user&.created_at
    return false if user_created_at && user_created_at.to_date >= FEATURE_ROLLOUT_DATE

    Date.current < FEATURE_ROLLOUT_DATE + BANNER_DURATION
  end

  def dossier_layout_in_rollout_transition_window?
    Date.current < FEATURE_ROLLOUT_DATE + BANNER_DURATION
  end

  def dossier_layout_toggle_label(current_mode)
    target = current_mode == :grid ? :stacked : :grid
    period = dossier_layout_in_rollout_transition_window? ? :during_rollout : :neutral
    I18n.t("instructeurs.dossier_layout.toggle.#{period}.switch_to_#{target}")
  end

  def dossier_layout_toggle_aria_label(current_mode)
    target = current_mode == :grid ? :stacked : :grid
    I18n.t("instructeurs.dossier_layout.toggle.aria_label_switch_to_#{target}")
  end

  def dossier_layout_toggle_icon_class(current_mode)
    # L'icône reflète le mode vers lequel on bascule.
    target = current_mode == :grid ? :stacked : :grid
    target == :grid ? 'fr-icon-layout-grid-fill' : 'fr-icon-list-unordered'
  end

  # pf: regroupe tous les data-values du Stimulus controller dossier-layout-toggle
  # pour éviter une ligne interminable dans le template HAML. Les libellés du bouton
  # sont pré-calculés côté serveur (le choix during_rollout/neutral vit dans le helper,
  # le JS ne fait que swapper entre 2 valeurs finales).
  def dossier_layout_toggle_data
    {
      controller: 'dossier-layout-toggle',
      'dossier-layout-toggle-url-grid-value': instructeur_dossier_layout_path(mode: :grid),
      'dossier-layout-toggle-url-stacked-value': instructeur_dossier_layout_path(mode: :stacked),
      'dossier-layout-toggle-live-grid-value': I18n.t('instructeurs.dossier_layout.toggle.live_grid'),
      'dossier-layout-toggle-live-stacked-value': I18n.t('instructeurs.dossier_layout.toggle.live_stacked'),
      'dossier-layout-toggle-live-error-value': I18n.t('instructeurs.dossier_layout.toggle.error'),
      'dossier-layout-toggle-label-when-grid-value': dossier_layout_toggle_label(:grid),
      'dossier-layout-toggle-label-when-stacked-value': dossier_layout_toggle_label(:stacked),
      'dossier-layout-toggle-aria-when-grid-value': dossier_layout_toggle_aria_label(:grid),
      'dossier-layout-toggle-aria-when-stacked-value': dossier_layout_toggle_aria_label(:stacked),
    }
  end
end
