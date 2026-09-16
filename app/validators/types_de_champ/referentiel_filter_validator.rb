# frozen_string_literal: true

# pf: cascade référentiel — un referentiel_de_polynesie filtré doit pointer un pilote encore
# admissible (présent, placé avant, à la racine ou dans la même ligne de bloc, de type texte/choix).
# Même régime que ConditionValidator : la suppression du pilote est autorisée, l'erreur apparaît
# dans l'éditeur (ErrorsSummary + champ) et bloque la publication jusqu'à correction.
class TypesDeChamp::ReferentielFilterValidator < ActiveModel::EachValidator
  def validate_each(procedure, collection, tdcs)
    return if tdcs.empty?

    revision = procedure.draft_revision
    tdcs_with_children(procedure, tdcs).each do |tdc|
      next unless tdc.referentiel_filter?

      coordinate = revision.coordinate_for(tdc)
      next if coordinate.nil?

      allowed_ids = coordinate.pilot_columns_for_referentiel_filter.map { _1.h_id[:column_id] }
      next if allowed_ids.include?(Hash(tdc.referentiel_filter)['pilot_column_id'].to_s)

      procedure.errors.add(
        collection,
        procedure.errors.generate_message(collection, :invalid_referentiel_filter, { value: tdc.libelle }),
        type_de_champ: tdc
      )
    end
  end

  private

  def tdcs_with_children(procedure, tdcs)
    tdcs.to_a.flat_map { _1.repetition? ? procedure.draft_revision.children_of(_1) : _1 }
  end
end
