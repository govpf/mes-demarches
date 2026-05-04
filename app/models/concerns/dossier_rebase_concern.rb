# frozen_string_literal: true

module DossierRebaseConcern
  RACE_CONDITION_DELAY = 30.seconds

  extend ActiveSupport::Concern

  def rebase!
    ProcedureRevisionPreloader.new([procedure.published_revision, revision].compact).all
    return if procedure.published_revision.blank?
    return if !can_rebase?

    transaction { rebase }
  end

  def rebase_later
    DossierRebaseJob.set(wait: RACE_CONDITION_DELAY).perform_later(self)
  end

  def can_rebase?
    procedure.published_revision.present? && revision != procedure.published_revision && !termine?
  end

  def pending_changes
    procedure.published_revision.present? ? revision.compare_types_de_champ(procedure.published_revision) : []
  end

  private

  def rebase
    # revision we are rebasing to
    target_revision = procedure.published_revision

    changed_stable_ids_by_op = pending_changes
      .group_by(&:op)
      .transform_values { _1.map(&:stable_id) }
    updated_stable_ids = changed_stable_ids_by_op.fetch(:update, [])
    added_stable_ids = changed_stable_ids_by_op.fetch(:add, [])

    # update dossier revision
    update_column(:revision_id, target_revision.id)

    # mark updated champs as rebased
    champs.where(stable_id: updated_stable_ids).update_all(rebased_at: Time.zone.now)

    # add rows for new repetitions
    target_revision
      .types_de_champ
      .filter { _1.repetition? && _1.stable_id.in?(added_stable_ids) && (_1.mandatory? || _1.private?) }
      .each do |type_de_champ|
        self.champs << type_de_champ.build_champ(row_id: ULID.generate, rebased_at: Time.zone.now)
      end

    # pf: Recalcul global des formules après rebase, qui couvre :
    # - formules AJOUTÉES par la nouvelle révision : champ_upsert_by!
    #   matérialise le champ en BDD (avant : colonne vide tant que l'usager
    #   ne touchait pas une source).
    # - formules dont l'EXPRESSION a changé (updated_stable_ids ∩ formules) :
    #   la valeur stockée devient stale, on la recalcule.
    # - formules dont une SOURCE a changé sémantiquement (type, options) :
    #   recalcul transitif via compute_formulas_in_order.
    #
    # L'association :revision en cache mémoire peut pointer sur l'ancienne
    # révision (update_column ne reset pas l'association), on la force à
    # target_revision pour que compute_formulas_in_order itère bien sur la
    # nouvelle révision.
    self.revision = target_revision
    # pf: rebase = écriture système. On force le stream main (la version
    # officielle de la formule, indépendante du buffer usager) et on passe
    # system_write: true pour bypasser check_valid_stream_on_write?, qui
    # interdirait sinon l'écriture main sur un dossier en_construction
    # (cas d'une formule publique ajoutée pendant que des dossiers sont
    # en cours de remplissage).
    with_main_stream do
      compute_formulas_in_order(system_write: true)
    end
  end
end
