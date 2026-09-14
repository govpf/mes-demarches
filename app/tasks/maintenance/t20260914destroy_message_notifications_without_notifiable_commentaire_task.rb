# frozen_string_literal: true

module Maintenance
  class T20260914destroyMessageNotificationsWithoutNotifiableCommentaireTask < MaintenanceTasks::Task
    # Documentation : pf: supprime les DossierNotification de type « message » dont le dossier
    # ne contient plus aucun commentaire notifiable pour l'instructeur concerné.
    # Nécessaire après l'ajout des expéditeurs automatisés (AUTOMATED_SENDER_EMAILS) aux
    # e-mails système : les notifications créées par leurs messages (au suivi d'un dossier,
    # au changement de préférences, aux demandes de correction) doivent disparaître.
    # Même règle que Commentaire.to_notify, corrélée sur le dossier et l'instructeur de la notification.

    include RunnableOnDeployConcern
    include StatementsHelpersConcern

    run_on_first_deploy

    def collection
      notifiable_commentaires = Commentaire
        .where("commentaires.dossier_id = dossier_notifications.dossier_id")
        .where.not(email: Commentaire::SYSTEM_EMAILS)
        .where(discarded_at: nil)
        .where("commentaires.instructeur_id IS NULL OR commentaires.instructeur_id != dossier_notifications.instructeur_id")

      DossierNotification
        .where(notification_type: :message)
        .where.not(notifiable_commentaires.arel.exists)
    end

    def process(notification)
      notification.destroy!
    end
  end
end
