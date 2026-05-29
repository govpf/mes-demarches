# frozen_string_literal: true

class Champs::RNAController < Champs::ChampController
  def show
    champs_attributes = params.dig(:dossier, :champs_public_attributes) || params.dig(:dossier, :champs_private_attributes)
    rna = champs_attributes.values.first[:value]

    @champ.fetch_association!(rna)
    @champ.update_timestamps
    # pf: cascade explicite des formules dépendantes après mise à jour des
    # données externes (data/value via fetch_association!). Le callback
    # after_save sur saved_change_to_value? ratait les modifications de data.
    @champ.dossier.refresh_formulas_after(@champ)
  end
end
