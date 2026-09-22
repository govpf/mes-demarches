# frozen_string_literal: true

module Maintenance
  class T20260921destroySeenDossierModifieNotificationsTask < MaintenanceTasks::Task
    # Documentation : pf: supprime les notifications « Dossier modifié » que l'instructeur a déjà
    # consultées, c'est-à-dire celles dont le suivi porte une date de consultation de la demande
    # (follows.demande_seen_at) postérieure à la dernière modification publique du dossier
    # (dernier champ public du flux principal, mise à jour de l'identité, ou dépôt).
    # Origine : jusqu'à ce jour, l'upload web d'une PJ d'annotation privée faisait avancer
    # dossiers.last_champ_updated_at (divergence avec upstream, corrigée dans
    # Champs::PieceJustificativeController). Le recalcul des notifications au premier suivi
    # (passage en instruction) posait alors un tag sur un dossier déjà consulté, qui restait
    # ensuite sur les dossiers terminés. Le critère upstream lui-même ignore demande_seen_at.

    include RunnableOnDeployConcern
    include StatementsHelpersConcern

    run_on_first_deploy

    def collection
      last_public_champ_change = Champ
        .where("champs.dossier_id = dossier_notifications.dossier_id")
        .where(private: false, stream: Champ::MAIN_STREAM)
        .select("MAX(champs.updated_at)")

      DossierNotification
        .where(notification_type: :dossier_modifie)
        .joins(:dossier)
        .joins("INNER JOIN follows ON follows.dossier_id = dossier_notifications.dossier_id " \
               "AND follows.instructeur_id = dossier_notifications.instructeur_id " \
               "AND follows.unfollowed_at IS NULL")
        .where.not(dossiers: { depose_at: nil })
        .where("follows.demande_seen_at >= GREATEST((#{last_public_champ_change.to_sql}), dossiers.identity_updated_at, dossiers.depose_at)")
    end

    def process(notification)
      notification.destroy!
    end

    def count
      with_statement_timeout("5min") do
        collection.count(:id)
      end
    end
  end
end
