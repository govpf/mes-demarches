# frozen_string_literal: true

# pf: Job quotidien qui recalcule les formules avec formule_deps['has_clock'] = true
# sur les dossiers actifs. Scope :
#   - brouillons : toutes les formules clock-dépendantes (publiques + privées).
#     Les formules publiques y sont dynamiques pour que l'usager qui revient
#     sur un brouillon voie un AGE à jour.
#   - dossiers en_construction / en_instruction / pending_correction : les
#     annotations privées clock-dépendantes uniquement. Les formules publiques
#     y sont figées (la valeur au dépôt reflète la demande au dépôt).
#
# Les dossiers terminaux (accepte/refuse/sans_suite) ne sont jamais touchés.
#
# Pour limiter la charge : on filtre au niveau SQL les révisions qui contiennent
# au moins un TDC formule avec formule_deps['has_clock'] = true, puis on enqueue
# un RefreshClockDependentFormulasDossierJob par dossier (parallélisation +
# isolation des erreurs par dossier).
class Cron::RefreshClockDependentFormulasJob < Cron::CronJob
  self.schedule_expression = "every day at 00:10"

  def perform
    revision_ids = revisions_with_clock_dependent_formula
    return if revision_ids.empty?

    enqueue_for(
      Dossier.state_brouillon.where(revision_id: revision_ids),
      scope: 'all'
    )
    enqueue_for(
      Dossier.state_en_construction_ou_instruction.where(revision_id: revision_ids),
      scope: 'private_only'
    )
  end

  private

  def revisions_with_clock_dependent_formula
    ProcedureRevisionTypeDeChamp
      .joins(:type_de_champ)
      .where(types_de_champ: { type_champ: 'formule' })
      .where("types_de_champ.options->'formule_deps'->>'has_clock' = 'true'")
      .distinct
      .pluck(:revision_id)
  end

  def enqueue_for(relation, scope:)
    relation.find_each do |dossier|
      RefreshClockDependentFormulasDossierJob.perform_later(dossier.id, scope)
    end
  end
end
