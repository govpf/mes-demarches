# frozen_string_literal: true

module Maintenance
  class T20251106backfillDossierNotificationForDossierExpirantTask < MaintenanceTasks::Task
    # Documentation: cette tâche permet de rattraper les badges de notifications
    # de type dossier_expirant

    include RunnableOnDeployConcern
    include StatementsHelpersConcern

    # pf: exécutée au déploiement — sans elle, les badges expirant/suppression
    # (upstream #12198) restent vides pour tous les dossiers existants.
    # Idempotente (find_or_create_by!).
    run_on_first_deploy

    def collection
      Dossier
        .termine_or_en_construction_close_to_expiration
        .includes(groupe_instructeur: :instructeurs)
    end

    def process(dossier)
      dossier.groupe_instructeur.instructeur_ids.each do |instructeur_id|
        DossierNotification.find_or_create_by!(
          dossier_id: dossier.id,
          notification_type: :dossier_expirant,
          instructeur_id: instructeur_id
        ) do |notification|
          notification.display_at = dossier.expired_at - Expired::REMAINING_WEEKS_BEFORE_EXPIRATION.weeks
        end
      end
    end

    def count
      with_statement_timeout("5min") do
        collection.count(:id)
      end
    end
  end
end
