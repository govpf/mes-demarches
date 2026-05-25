# frozen_string_literal: true

# pf: préserve les défauts PF historiques (cf. migration 20230907 sur assign_tos)
# après la migration upstream des préférences email vers instructeurs_procedures
# (upstream 20251104, phase 1/3 du transfert). Sans cet override, toute nouvelle
# affectation d'instructeur (notamment via insert_all dans ensure_instructeur_procedures_for)
# créerait une row avec instant_email_new_*: false, contredisant la politique PF.
class ChangeDefaultValuesForInstructeursProcedureEmailPreferences < ActiveRecord::Migration[7.2]
  def change
    change_column_default :instructeurs_procedures, :instant_email_new_dossier, from: false, to: true
    change_column_default :instructeurs_procedures, :instant_email_new_message, from: false, to: true
  end
end
