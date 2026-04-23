# frozen_string_literal: true

class Instructeurs::PfFullTextSearchInputComponent < ApplicationComponent
  def initialize(procedure_presentation:, statut:)
    @procedure_presentation = procedure_presentation
    @statut = statut
  end

  def current_query
    @procedure_presentation.current_full_text_filter_for(@statut)&.filter_value&.first.to_s
  end

  def form_url
    set_full_text_filter_instructeur_procedure_presentation_path(@procedure_presentation)
  end
end
