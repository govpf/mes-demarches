# frozen_string_literal: true

class InstructeursProcedure < ApplicationRecord
  NOTIFICATION_PREFERENCES = ['all', 'followed', 'none'].freeze

  DEFAULT_NOTIFICATIONS_PREFERENCES = {
    dossier_depose: 'all',
    dossier_modifie: 'followed',
    message: 'followed',
    annotation_instructeur: 'followed',
    avis_externe: 'followed',
    attente_correction: 'followed',
    attente_avis: 'followed',
    attente_reponse: 'followed',
  }.freeze

  NOTIFICATION_COLUMNS = {
    dossier_depose: 'display_dossier_depose_notifications',
    dossier_modifie: 'display_dossier_modifie_notifications',
    message: 'display_message_notifications',
    annotation_instructeur: 'display_annotation_instructeur_notifications',
    avis_externe: 'display_avis_externe_notifications',
    attente_correction: 'display_attente_correction_notifications',
    attente_avis: 'display_attente_avis_notifications',
    attente_reponse: 'display_attente_reponse_notifications',
  }.freeze

  belongs_to :instructeur
  belongs_to :procedure

  validates :display_dossier_depose_notifications, inclusion: { in: NOTIFICATION_PREFERENCES - ['followed'] }
  validates :display_dossier_modifie_notifications, inclusion: { in: NOTIFICATION_PREFERENCES }
  validates :display_message_notifications, inclusion: { in: NOTIFICATION_PREFERENCES }
  validates :display_annotation_instructeur_notifications, inclusion: { in: NOTIFICATION_PREFERENCES }
  validates :display_avis_externe_notifications, inclusion: { in: NOTIFICATION_PREFERENCES }
  validates :display_attente_correction_notifications, inclusion: { in: NOTIFICATION_PREFERENCES }
  validates :display_attente_avis_notifications, inclusion: { in: NOTIFICATION_PREFERENCES }
  validates :display_attente_reponse_notifications, inclusion: { in: NOTIFICATION_PREFERENCES }

  def self.update_instructeur_procedures_positions(instructeur, ordered_procedure_ids)
    procedure_id_position = ordered_procedure_ids.reverse.each.with_index.to_h
    InstructeursProcedure.transaction do
      procedure_id_position.each do |procedure_id, position|
        InstructeursProcedure.where(procedure_id:, instructeur:).update(position:)
      end
    end
  end

  # pf: nombre de jours sans consultation au-delà duquel un instructeur est considéré inactif sur une démarche
  MIN_INACTIVE_DAYS = 40

  # pf: coupe l'e-mail instantané « nouveau dossier » des instructeurs inactifs sur une démarche.
  # Porté depuis AssignTo quand upstream a déplacé les préférences e-mail vers instructeurs_procedures.
  def self.cancel_instant_email_new_dossier_for_inactive_instructeurs
    stale = where(instant_email_new_dossier: true, updated_at: ...MIN_INACTIVE_DAYS.days.ago)

    # l'instructeur a suivi des dossiers de la démarche mais n'en a consulté aucun depuis MIN_INACTIVE_DAYS
    seen_long_ago = stale
      .joins(instructeur: { all_follows: { dossier: :revision } })
      .where("procedure_revisions.procedure_id = instructeurs_procedures.procedure_id")
      .group("instructeurs_procedures.id")
      .having('max(greatest(follows.demande_seen_at, follows.messagerie_seen_at, follows.annotations_privees_seen_at, follows.avis_seen_at)) < ?', MIN_INACTIVE_DAYS.days.ago)
    where(id: seen_long_ago.select(:id)).update_all(instant_email_new_dossier: false)

    # l'instructeur n'a jamais suivi le moindre dossier
    never_followed = stale
      .left_outer_joins(instructeur: :all_follows)
      .where(follows: { id: nil })
    where(id: never_followed.select(:id)).update_all(instant_email_new_dossier: false)
  end

  def notification_preferences
    NOTIFICATION_COLUMNS.transform_values do |column|
      self.public_send(column)
    end
  end

  def notification_preference_for(notification_type)
    self.public_send(NOTIFICATION_COLUMNS[notification_type])
  end

  def refresh_notifications(groupe_instructeur_ids, old_preferences, new_preferences)
    return if old_preferences == new_preferences

    old_preferences.keys.each do |notification_type|
      if old_preferences[notification_type] != new_preferences[notification_type]
        DossierNotification.refresh_notifications_instructeur_for_dossiers(
          groupe_instructeur_ids,
          instructeur_id,
          notification_type,
          old_preferences[notification_type],
          new_preferences[notification_type]
        )
      end
    end
  end
end
