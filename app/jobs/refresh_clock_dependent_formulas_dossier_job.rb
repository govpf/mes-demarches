# frozen_string_literal: true

# pf: Job par-dossier enqueué par Cron::RefreshClockDependentFormulasJob.
# Isole les erreurs (un dossier pourri ne bloque pas les autres) et répartit
# la charge Sidekiq. Ignore silencieusement les dossiers qui ont changé d'état
# entre l'enqueue et l'exécution (ex: dossier accepté entre-temps).
class RefreshClockDependentFormulasDossierJob < ApplicationJob
  queue_as :default

  def perform(dossier_id, scope_str)
    dossier = Dossier.find_by(id: dossier_id)
    return if dossier.nil?
    return if dossier.termine?

    # pf: re-vérifie le scope applicable à l'état courant, au cas où le
    # dossier a été déposé entre l'enqueue et l'exécution.
    effective_scope = dossier.brouillon? ? :all : :private_only
    requested_scope = scope_str.to_sym

    # On applique le plus restrictif des deux (si on était parti sur :all
    # mais que le dossier est passé en_construction, on ne refait que les
    # privées).
    scope = [requested_scope, effective_scope].include?(:private_only) ? :private_only : :all

    dossier.refresh_clock_dependent_formulas(scope: scope)
  end
end
