# frozen_string_literal: true

class Procedure::Card::AttestationComponent < ApplicationComponent
  def initialize(procedure:)
    @procedure = procedure
  end

  private

  def edit_attestation_path
    # pf-v1-compat: routing conditionnel temporaire pour migration graduelle
    # À supprimer quand tous les usagers PF seront migrés vers v2
    if @procedure.attestation_templates_v2.any? || @procedure.feature_enabled?(:attestation_v2)
      helpers.edit_admin_procedure_attestation_template_v2_path(@procedure)
    else
      # pf-v1-compat: fallback v1 temporaire
      helpers.edit_admin_procedure_attestation_template_path(@procedure)
    end
  end

  def error_messages
    @procedure.errors.messages_for(:attestation_template).to_sentence
  end
end
