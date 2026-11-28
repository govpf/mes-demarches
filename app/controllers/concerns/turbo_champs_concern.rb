# frozen_string_literal: true

module TurboChampsConcern
  extend ActiveSupport::Concern

  private

  def champs_to_turbo_update(params, champs)
    to_update = champs.filter { _1.public_id.in?(params.keys) }
      .filter { _1.refresh_after_update? || _1.user_buffer_changes? }
    prefillable_champs = champs.filter { it.referentiel? && it.autocomplete? }
    to_update += prefillable_champs.map(&:prefillable_champs).flatten.uniq if prefillable_champs.any?

    # pf: formules en aval (transitif) des champs modifiés, via Dossier#formula_champs_downstream_of
    updated_champs = champs.filter { _1.public_id.in?(params.keys) }
    to_update += updated_champs.flat_map { _1.dossier.formula_champs_downstream_of(_1) }.uniq
    # pf: cascade référentiel — re-rendre les référentiels dont le pilote vient de changer
    to_update += updated_champs.flat_map(&:dependent_referentiel_filter_champs).uniq(&:public_id)
    to_show, to_hide = champs.filter { it.conditional? || it.child? }
      .partition(&:visible?)
      .map { champs_to_one_selector(_1 - to_update) }

    return to_show, to_hide, to_update
  end

  def champs_to_one_selector(champs)
    champs
      .map { "##{_1.input_group_id}" }
      .join(',')
  end
end
