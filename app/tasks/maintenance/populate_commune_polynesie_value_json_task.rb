# frozen_string_literal: true

module Maintenance
  # pf: Normalise les champs Commune/Code postal de Polynésie historiques vers
  # value_json. Ces champs ne stockaient que `archipel` (voire rien) dans
  # value_json ; ile/code_postal/commune étaient recalculés à la volée via
  # APIGeo à chaque lecture. On peuple désormais le cache value_json complet
  # pour que les JSONPathColumn (filtres, tableaux instructeur, exports template,
  # formules) puissent les lire. Aligné sur PopulateSiretValueJSONTask.
  #
  # APIGeo::API utilise une source de communes en mémoire (pas d'appel HTTP),
  # donc le backfill est peu coûteux.
  class PopulateCommunePolynesieValueJSONTask < MaintenanceTasks::Task
    include RunnableOnDeployConcern

    run_on_first_deploy

    def collection
      Champ
        .where(type: ['Champs::CommuneDePolynesieChamp', 'Champs::CodePostalDePolynesieChamp'])
        .where.not(value: [nil, ''])
        .where("value_json->>'ile' IS NULL")
    end

    def process(champ)
      # pf: on_value_change (déclenché par le before_save) repeuple value_json
      # depuis APIGeo. On force le recalcul puis on persiste sans toucher au reste.
      champ.send(:on_value_change)
      champ.update_columns(value_json: champ.value_json)
    rescue StandardError => e
      Rails.logger.warn("PopulateCommunePolynesieValueJSON skip champ ##{champ.id}: #{e.class} #{e.message}")
    end

    def count
      # noop: gros volumes, le comptage déclenche un PG statement timeout
    end
  end
end
