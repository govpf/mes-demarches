# frozen_string_literal: true

module Maintenance
  # pf: fige dans referentiel_mapping l’affichage instructeur hérité de la colonne
  # « Champs instructeur » de la table méta Baserow, avant que le code cesse de la lire
  # (branche legacy de TypesDeChamp::ReferentielDePolynesieTypeDeChamp#paths).
  # Seuls les champs qui dépendaient encore de cette branche sont touchés : aucun mapping, ou un
  # mapping où rien n’est affiché à l’instructeur. « Champs usager » n’est pas repris (décision du
  # 2026-09-17) : l’affichage usager passait déjà exclusivement par le mapping.
  # Idempotente et relançable : un champ dont Baserow est injoignable est laissé intact.
  class T20260917migrateBaserowMetaColumnsToMappingTask < MaintenanceTasks::Task
    include RunnableOnDeployConcern

    run_on_first_deploy

    def collection
      TypeDeChamp.where(type_champ: TypeDeChamp.type_champs.fetch(:referentiel_de_polynesie))
    end

    def process(type_de_champ)
      return if type_de_champ.referentiel_mapping_displayable_for_instructeur.any?

      table_id = type_de_champ.table_id
      return if table_id.blank?

      field_ids = ReferentielDePolynesie::API.config(table_id)&.dig('Champs instructeur')
      return if field_ids.blank?

      fields = ReferentielDePolynesie::API.table_fields(table_id)
      if fields.nil?
        Rails.logger.warn("MigrateBaserowMetaColumnsToMapping: colonnes Baserow indisponibles, TDC ##{type_de_champ.id} (table #{table_id}) laissé intact")
        return
      end

      mapping = type_de_champ.safe_referentiel_mapping.to_h
      field_ids.split(',').map(&:strip).each do |field_id|
        field = fields[field_id.to_i]
        next if field.nil? # colonne supprimée côté Baserow depuis

        jsonpath = "$.#{field[:name]}"
        entry = mapping[jsonpath] || {
          'type' => ReferentielDePolynesie::BaserowAPI.baserow_type_to_mapping_type(field),
          'libelle' => field[:name],
          'prefill' => '0',
          'display_usager' => '0',
        }
        mapping[jsonpath] = entry.merge('display_instructeur' => '1')
      end

      type_de_champ.update_column(:options, type_de_champ.options.merge('referentiel_mapping' => mapping))
    end
  end
end
