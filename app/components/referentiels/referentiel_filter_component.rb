# frozen_string_literal: true

# pf: cascade — troisième section du panneau « préremplir et afficher » : restreindre les lignes
# proposées par le référentiel de Polynésie selon un champ du formulaire (colonne Baserow ↔ pilote).
# Vit ici, avec le préremplissage et l’affichage, parce qu’il relie les colonnes Baserow au
# formulaire ; la carte du champ ne garde qu’un rappel en lecture seule.
class Referentiels::ReferentielFilterComponent < Referentiels::MappingFormBase
  def render?
    type_de_champ.referentiel_de_polynesie? && type_de_champ.table_id.present?
  end

  def enabled?
    type_de_champ.referentiel_filter?
  end

  def current_value(key)
    Hash(type_de_champ.referentiel_filter)[key.to_s]
  end

  # pf: colonnes Baserow filtrables ; repli sur la colonne en cache si Baserow est injoignable
  def baserow_options
    return @baserow_options if defined?(@baserow_options)

    fields = fetch_fields
    @fields_unavailable = fields.nil?

    options = Hash(fields).filter_map do |id, field|
      [field[:name], id] if field[:type].in?(ReferentielDePolynesie::ContextualFilter::FILTERABLE_BASEROW_TYPES)
    end
    if options.empty? && current_value(:baserow_field_id).present?
      options = [[current_value(:baserow_field_name), current_value(:baserow_field_id).to_i]]
    end
    @baserow_options = options
  end

  def fields_unavailable?
    baserow_options
    @fields_unavailable
  end

  # pf: champs pilotes admissibles (cf. ProcedureRevisionTypeDeChamp)
  def pilot_options
    coordinate = procedure.draft_revision.coordinate_for(type_de_champ)
    return [] if coordinate.nil?

    coordinate.pilot_columns_for_referentiel_filter.map { [_1.label, _1.h_id[:column_id]] }
  end

  def field_id(suffix) = "referentiel-filter-#{type_de_champ.stable_id}-#{suffix}"

  private

  # pf: repli sur nil si Baserow est injoignable (cf. baserow_options)
  def fetch_fields
    ReferentielDePolynesie::API.table_fields(type_de_champ.table_id)
  rescue StandardError
    nil
  end
end
