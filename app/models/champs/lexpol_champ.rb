# frozen_string_literal: true

class Champs::LexpolChamp < Champ
  store_accessor :data, :lexpol_status, :lexpol_dossier_url, :lexpol_arrete_lien

  # pf: pour les ancres d'erreur (#11420), le component utilise html_id sans suffixe -input
  def focusable_input_id
    html_id
  end
end
