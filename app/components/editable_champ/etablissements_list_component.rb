# frozen_string_literal: true

# pf: rendered when a Champs::SiretChamp is in multiple_found state
# (ambiguous partial Tahiti number matching several etablissements).
# Presents the candidates list and lets the user pick one to complete the number.
class EditableChamp::EtablissementsListComponent < ApplicationComponent
  def initialize(champ:)
    @champ = champ
    @etablissements = champ.etablissement_candidates
    @input_id = champ.focusable_input_id
    @siret_prefix = champ.external_id
  end
end
