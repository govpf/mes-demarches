# frozen_string_literal: true

class Instructeurs::EditableFiltersComponent < ApplicationComponent
  attr_reader :procedure_presentation, :statut, :instructeur_procedure

  def initialize(procedure_presentation:, instructeur_procedure:, statut:)
    @procedure_presentation = procedure_presentation
    @instructeur_procedure = instructeur_procedure
    @statut = statut
  end

  def id
    "editable-filters-component"
  end

  def render?
    filters.any?
  end

  def filters
    # pf: exclu du formulaire éditable upstream — la barre dédiée au-dessus de
    # la table gère déjà ce filtre, le réafficher ici créerait une zone redondante
    procedure_presentation.filters_for(statut).reject { _1.column.is_a?(Columns::PfFullTextColumn) }
  end
end
