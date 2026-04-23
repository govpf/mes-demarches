# frozen_string_literal: true

# pf: filtre full-text unique par statut. Surcharge
# add_filter_for_statut! via prepend pour garantir l'unicité même
# quand l'ajout passe par le picker de filtres standard.
module PfFullTextFilterConcern
  extend ActiveSupport::Concern

  module Override
    def add_filter_for_statut!(statut, filter)
      return set_full_text_filter_for_statut!(statut, filter) if filter.column.is_a?(Columns::PfFullTextColumn)

      super
    end
  end

  included do
    prepend Override

    def current_full_text_filter_for(statut)
      filters_for(statut).to_a.find { |fc| fc.column.is_a?(Columns::PfFullTextColumn) }
    end

    def set_full_text_filter_for_statut!(statut, filter)
      filters_attr = filters_name_for(statut)
      current = (send(filters_attr) || []).reject { |fc| fc.column.is_a?(Columns::PfFullTextColumn) }
      update!(filters_attr => filter.present? ? current + [filter] : current)
    end
  end
end
