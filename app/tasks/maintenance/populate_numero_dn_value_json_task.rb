# frozen_string_literal: true

module Maintenance
  # pf: Normalise les champs Numéro DN historiques vers value_json.
  # NumeroDnChamp stocke aujourd'hui numero_dn + date_de_naissance dans
  # value_json (store_accessor), mais conserve aussi un packing legacy dans
  # `value` (JSON.generate([numero_dn, date_de_naissance])). Les champs créés
  # avant l'arrivée du store_accessor n'ont que ce packing legacy et pas de
  # value_json — donc la JSONPathColumn date_de_naissance (filtres, exports,
  # formules) ne voit rien. Ce backfill reconstruit value_json depuis `value`.
  # Aligné sur PopulateSiretValueJSONTask / PopulateRNFJSONValueTask.
  class PopulateNumeroDnValueJSONTask < MaintenanceTasks::Task
    include RunnableOnDeployConcern

    run_on_first_deploy

    def collection
      Champs::NumeroDnChamp
        .where.not(value: nil)
        .where("value_json->>'date_de_naissance' IS NULL")
    end

    def process(champ)
      parsed = parse_legacy_value(champ.value)
      return unless parsed.is_a?(Array) && parsed.size == 2

      numero_dn, date_de_naissance = parsed
      champ.update_columns(value_json: { 'numero_dn' => numero_dn, 'date_de_naissance' => date_de_naissance })
    end

    def parse_legacy_value(value)
      JSON.parse(value)
    rescue JSON::ParserError, TypeError
      nil
    end

    def count
      # noop: gros volumes, le comptage déclenche un PG statement timeout
    end
  end
end
