# frozen_string_literal: true

class Champs::LexpolChamp < Champ
  # pf: lexpol_auteur_email = compte Lexpol qui a créé le dossier (seul à le voir tant qu'il est
  # « En préparation »), utilisé en premier par le rafraîchissement matinal
  store_accessor :data, :lexpol_status, :lexpol_dossier_url, :lexpol_arrete_lien, :lexpol_auteur_email

  # pf: pour les ancres d'erreur (#11420), le component utilise html_id sans suffixe -input
  def focusable_input_id(attribute = :value)
    html_id
  end
end
