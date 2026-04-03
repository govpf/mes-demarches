# frozen_string_literal: true

class EditableChamp::SiretComponent < EditableChamp::EditableChampBaseComponent
  include EtablissementHelper

  # pf: keep @attribute as :value (not :external_id) because PF uses synchronous
  # SIRET/TAHITI logic via SiretChampEtablissementFetchableConcern, not the upstream state machine

  def dsfr_input_classname
    'fr-input'
  end

  # pf: needed by the turbo-input in siret_component.html.haml to call our PF SiretController
  def update_path
    champs_siret_path(@champ.dossier, @champ.stable_id, row_id: @champ.row_id)
  end

  def hint_id
    dom_id(@champ, :siret_info)
  end

  def hintable?
    true
  end
end
