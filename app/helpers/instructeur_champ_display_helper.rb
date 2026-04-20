# frozen_string_literal: true

# pf: helper centralisé pour la largeur d'affichage des champs côté instructeur.
# Concentré ici pour éviter d'override display_width dans chaque dynamic_type
# (minimise la divergence upstream sur app/models/types_de_champ/*).
module InstructeurChampDisplayHelper
  TYPE_CHAMP_TO_DISPLAY_WIDTH = {
    # full : largeur totale (champs structurels ou à contenu long/visuel)
    header_section: :full,
    explication: :full,
    textarea: :full,
    repetition: :full,
    carte: :full,
    dossier_link: :full,
    piece_justificative: :full,
    titre_identite: :full,
    referentiel_de_polynesie: :full,
    te_fenua: :full,
    engagement_juridique: :full,
    formule: :full,
    # quarter : booléens / signatures courtes (4 par ligne)
    checkbox: :quarter,
    yes_no: :quarter,
    visa: :quarter
    # default = :half pour tous les autres (text, email, phone, date, numbers, dropdowns, etc.)
  }.freeze

  def champ_display_width(champ)
    TYPE_CHAMP_TO_DISPLAY_WIDTH.fetch(champ.type_champ.to_sym, :half)
  end

  def champ_display_width_class(champ)
    "champ-grid-item--#{champ_display_width(champ)}"
  end
end
