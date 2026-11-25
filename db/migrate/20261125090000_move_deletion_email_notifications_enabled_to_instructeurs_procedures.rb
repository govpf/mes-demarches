# frozen_string_literal: true

# pf: la préférence PF « e-mail de suppression automatique » suit les autres préférences e-mail,
# qu'upstream a déplacées d'assign_tos vers instructeurs_procedures (#12401).
# La reprise est faite ici en SQL : seuls les refus explicites (false) sont à reporter, le défaut
# restant true. Un instructeur qui a coupé la notification sur au moins un groupe de la démarche
# la garde coupée ; sa ligne instructeurs_procedures est créée si elle n'existe pas encore.
class MoveDeletionEmailNotificationsEnabledToInstructeursProcedures < ActiveRecord::Migration[7.2]
  def up
    add_column :instructeurs_procedures, :deletion_email_notifications_enabled, :boolean, default: true, null: false

    safety_assured do
      execute <<~SQL.squish
        INSERT INTO instructeurs_procedures
          (instructeur_id, procedure_id, position, last_revision_seen_id, deletion_email_notifications_enabled, created_at, updated_at)
        SELECT
          opt_out.instructeur_id,
          opt_out.procedure_id,
          COALESCE((SELECT MAX(ip.position) FROM instructeurs_procedures ip WHERE ip.instructeur_id = opt_out.instructeur_id), 0)
            + ROW_NUMBER() OVER (PARTITION BY opt_out.instructeur_id ORDER BY opt_out.procedure_id),
          opt_out.published_revision_id,
          FALSE,
          NOW(),
          NOW()
        FROM (
          SELECT DISTINCT assign_tos.instructeur_id, groupe_instructeurs.procedure_id, procedures.published_revision_id
          FROM assign_tos
          INNER JOIN groupe_instructeurs ON groupe_instructeurs.id = assign_tos.groupe_instructeur_id
          INNER JOIN procedures ON procedures.id = groupe_instructeurs.procedure_id
          WHERE assign_tos.deletion_email_notifications_enabled = FALSE
        ) opt_out
        ON CONFLICT (instructeur_id, procedure_id)
        DO UPDATE SET deletion_email_notifications_enabled = FALSE
      SQL
    end
  end

  def down
    remove_column :instructeurs_procedures, :deletion_email_notifications_enabled
  end
end
