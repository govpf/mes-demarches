# frozen_string_literal: true

module Instructeurs
  class ProcedurePresentationController < InstructeurController
    before_action :set_procedure_presentation, only: [:update]

    def update
      if !@procedure_presentation.update(procedure_presentation_params)
        # complicated way to display inner error messages
        flash.alert = @procedure_presentation.errors
          .flat_map { _1.detail[:value].flat_map { |c| c.errors.full_messages } }
      end

      redirect_back_or_to([:instructeur, procedure])
    end

    def refresh_column_filter
      # Find the new filter by counting occurrences in params vs existing filters
      # This handles cases where:
      # 1. Params order varies (filters grouped separately from ids)
      # 2. Multiple filters on the same column are allowed
      procedure_presentation = ProcedurePresentation.find(params[:id])
      statut = params[:statut] || 'tous'

      existing_filter_ids = procedure_presentation.filters_for(statut).map { |f| f.column.id }
      param_filter_ids = params['filters'].filter_map { |f| (f['id'].presence) }

      # Count occurrences of each id
      existing_counts = existing_filter_ids.tally
      param_counts = param_filter_ids.tally

      # The new filter is the one that appears more times in params than in existing
      new_filter_id = param_counts.find { |id, count| count > (existing_counts[id] || 0) }&.first

      column = ColumnType.new.cast(new_filter_id)

      if column.groupe_instructeur?
        column.options_for_select = instructeur_groupes(procedure_id: column.h_id[:procedure_id])
      end

      component = Instructeurs::ColumnFilterValueComponent.new(column:)

      render turbo_stream: turbo_stream.replace('value', component)
    end

    private

    def procedure = @procedure_presentation.procedure

    def procedure_presentation_params
      h = params.permit(displayed_columns: [], sorted_column: [:order, :id], filters: [:id, :filter]).to_h

      if params[:statut].present?
        filter_name = @procedure_presentation.filters_name_for(params[:statut])
        h[filter_name] = h.delete("filters") # move filters to the right key, ex: tous_filters
      end

      # React ComboBox/MultiComboBox return [''] when no value is selected
      # We need to remove them
      if h[:displayed_columns].present?
        h[:displayed_columns] = h[:displayed_columns].reject(&:empty?)
      end

      h
    end

    def set_procedure_presentation
      @procedure_presentation = ProcedurePresentation
        .includes(:assign_to)
        .find_by!(id: params[:id], assign_to: { instructeur: current_instructeur })
    end

    def instructeur_groupes(procedure_id:)
      current_instructeur.groupe_instructeurs
        .filter_map { [_1.label, _1.id] if _1.procedure_id == procedure_id }
    end
  end
end
