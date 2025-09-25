# frozen_string_literal: true

class Champs::SiretController < Champs::ChampController
  def show
    champs_attributes = params.dig(:dossier, :champs_public_attributes) || params.dig(:dossier, :champs_private_attributes)
    siret = champs_attributes.values.first[:value]

    @champ.fetch_etablissement!(siret, current_user)

    # pf: Handle different cases for PF (multiple establishments, errors)
    if @champ.etablissement_fetch_error_key.present?
      # Real error case
      @siret = @champ.etablissement_fetch_error_key
      @multiple_etablissements = false
    elsif @champ.etablissement.present?
      # Single establishment found and created
      @siret = @champ.etablissement.siret
      @multiple_etablissements = false
    elsif @champ.etablissements.present?
      # pf: Multiple establishments found (not an error, requires user selection)
      @siret = siret
      @multiple_etablissements = true
    else
      # Other cases
      @siret = siret
      @multiple_etablissements = false
    end

    @champ.validate(params[:validate].to_sym) if params[:validate]

    @champ.dossier.touch_champs_changed([:last_champ_updated_at])
  end
end
