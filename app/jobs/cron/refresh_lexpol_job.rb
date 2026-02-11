# frozen_string_literal: true

# pf: Job cron pour rafraîchir les champs Lexpol le matin (après publication JOPF)
# Planification : tous les jours à 5h00
#
# Rafraîchit uniquement les champs Lexpol :
# - Dossiers EN INSTRUCTION
# - Ayant un NOR
# - N'ayant PAS ENCORE de lien arrêté (car une fois présent, il est immuable)
class Cron::RefreshLexpolJob < Cron::CronJob
  self.schedule_expression = "every day at 5 am"

  def perform(*args)
    lexpol_champs = find_active_lexpol_champs

    Rails.logger.info("Lexpol: Starting refresh for #{lexpol_champs.count} champs (en instruction, sans lien arrêté)")

    # pf: Enqueuer un job individuel pour chaque champ
    # Cela permet de paralléliser et de ne pas bloquer en cas d'erreur sur un champ
    lexpol_champs.find_each do |champ|
      RefreshLexpolChampJob.perform_later(champ.id)
    end

    Rails.logger.info("Lexpol: #{lexpol_champs.count} refresh jobs enqueued successfully")
  end

  private

  # pf: Trouve les champs Lexpol "actifs" à rafraîchir
  # Critères :
  # 1. Dossiers EN INSTRUCTION uniquement (pas les acceptés : le mail est déjà parti)
  # 2. Ayant un NOR (value présente)
  # 3. N'ayant PAS ENCORE de lien arrêté (lexpol_arrete_lien vide)
  #    → Car une fois présent, le lien est immuable (publication JOPF définitive)
  def find_active_lexpol_champs
    Champs::LexpolChamp
      .joins(:dossier)
      .merge(Dossier.state_en_instruction)
      .where.not(value: nil)
      .where.not(value: '')
      .where("data->>'lexpol_arrete_lien' IS NULL OR data->>'lexpol_arrete_lien' = ''")
  end
end
