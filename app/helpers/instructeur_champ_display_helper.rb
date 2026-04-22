# frozen_string_literal: true

# pf: helper centralisé pour la largeur d'affichage des champs côté instructeur.
# Concentré ici pour éviter d'override display_width dans chaque dynamic_type
# (minimise la divergence upstream sur app/models/types_de_champ/*).
module InstructeurChampDisplayHelper
  LAYOUT_COOKIE = :md_instructeur_dossier_layout
  LAYOUT_MODES = [:grid, :stacked].freeze

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
    formule: :full,
    piece_justificative: :full,
    titre_identite: :full,
    # half : contenu de taille moyenne
    siret: :half,
    iban: :half,
    address: :half,
    multiple_drop_down_list: :half
    # default = :quarter pour tout le reste
  }.freeze

  def champ_display_width(champ)
    TYPE_CHAMP_TO_DISPLAY_WIDTH.fetch(champ.type_champ.to_sym, :quarter)
  end

  def champ_display_width_class(champ)
    "champ-grid-item--#{champ_display_width(champ)}"
  end

  def instructeur_champs_layout_mode
    value = cookies[LAYOUT_COOKIE]&.to_sym
    LAYOUT_MODES.include?(value) ? value : :grid
  end

  def instructeur_champs_layout_chosen?
    cookies[LAYOUT_COOKIE].present?
  end
end
