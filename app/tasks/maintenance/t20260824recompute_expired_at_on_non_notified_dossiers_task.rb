# frozen_string_literal: true

module Maintenance
  class T20260824recomputeExpiredAtOnNonNotifiedDossiersTask < MaintenanceTasks::Task
    # Documentation: recalcule dossiers.expired_at pour les dossiers n'ayant reçu
    # aucun avertissement d'expiration. Avant le fix upstream 65a3c2d3e9,
    # ResetExpiringDossiersJob ne recalculait expired_at que pour les dossiers
    # déjà avertis : quand un administrateur augmentait la durée de conservation
    # d'une procédure, les dossiers non avertis gardaient une date calculée avec
    # l'ancienne durée, et recevaient donc l'avertissement (puis la suppression)
    # trop tôt. Cette tâche réaligne ces dates.
    # Les dossiers déjà avertis ne sont volontairement pas touchés : annuler une
    # notice ne se justifie que sur une procédure réellement rallongée, en
    # rejouant ResetExpiringDossiersJob procédure par procédure.

    include RunnableOnDeployConcern

    run_on_first_deploy

    def collection
      Dossier
        .where(brouillon_close_to_expiration_notice_sent_at: nil,
               en_construction_close_to_expiration_notice_sent_at: nil,
               termine_close_to_expiration_notice_sent_at: nil)
        .where.not(state: 'en_instruction')
    end

    def process(dossier)
      dossier.update_expired_at
    end

    def count
      # noop
    end
  end
end
