# frozen_string_literal: true

namespace :after_party do
  desc 'Deployment task: Enable referentiel_de_polynesie feature flag'
  task feature_flag_referentiel_de_polynesie: :environment do
    puts "Running deploy task 'feature_flag_referentiel_de_polynesie'"

    # Activer le feature flag pour referentiel_de_polynesie
    if Flipper.enabled?(:referentiel_de_polynesie)
      puts "Feature flag :referentiel_de_polynesie déjà activé"
    else
      Flipper.enable(:referentiel_de_polynesie)
      puts "Feature flag :referentiel_de_polynesie activé avec succès"
    end

    # Vérifier que le flag est bien activé
    if Flipper.enabled?(:referentiel_de_polynesie)
      puts "✅ Vérification: Feature flag :referentiel_de_polynesie est activé"
    else
      puts "❌ Erreur: Feature flag :referentiel_de_polynesie n'a pas pu être activé"
      exit 1
    end

    # Update task as completed.  If you remove the line below, the task will
    # run with every deploy (and fail if the code is not compatible).
    AfterParty::TaskRecord
      .create version: AfterParty::TaskRecorder.new(__FILE__).timestamp
  end
end
