# frozen_string_literal: true

class Columns::PfFullTextColumn < Column
  def initialize(procedure_id:)
    super(
      procedure_id:,
      table: 'pf',
      column: 'full_text',
      label: 'Recherche',
      type: :text,
      displayable: false,
      mandatory: false
    )
  end

  def filtered_ids(dossiers, filter)
    search_terms = filter[:value]&.first.to_s.strip
    return dossiers.ids if search_terms.blank?

    DossierSearchService.matching_dossiers(dossiers, search_terms, true)
  end
end
