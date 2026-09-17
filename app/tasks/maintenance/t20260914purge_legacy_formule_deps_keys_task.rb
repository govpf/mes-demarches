# frozen_string_literal: true

module Maintenance
  class T20260914purgeLegacyFormuleDepsKeysTask < MaintenanceTasks::Task
    # pf: Purge des clés d'options `clock_dependent` et `state_dependent` sur les
    # TDC formule. Ces flags ont été remplacés par le Hash `formule_deps`
    # (`has_clock` / `has_state`) mais la migration 20260522174323 les a laissés
    # en place (options.merge sans except). Plus aucun code ne les lit : on les
    # retire pour éviter qu'ils ne repartent dans les exports / clones de TDC.
    # update_column : pas de callbacks, donc ni re-validation de l'expression
    # ni cascade de recalcul.

    include RunnableOnDeployConcern

    run_on_first_deploy

    LEGACY_KEYS = ['clock_dependent', 'state_dependent'].freeze

    def collection
      TypeDeChamp
        .where(type_champ: 'formule')
        .where("options ? 'clock_dependent' OR options ? 'state_dependent'")
    end

    def process(type_de_champ)
      options = type_de_champ.options || {}
      return unless LEGACY_KEYS.any? { |key| options.key?(key) }

      type_de_champ.update_column(:options, options.except(*LEGACY_KEYS))
    end

    def count
      # noop
    end
  end
end
