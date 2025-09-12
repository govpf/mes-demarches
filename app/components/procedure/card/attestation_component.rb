# frozen_string_literal: true

class Procedure::Card::AttestationComponent < ApplicationComponent
  def initialize(procedure:)
    @procedure = procedure
  end

  private

  def edit_attestation_path
    # pf: préservation accès attestations v1 pour migration graduelle
    # Cette logique conditionnelle permet aux procédures existantes de continuer
    # à utiliser l'interface v1 tant qu'elles n'ont pas migré vers v2
    if @procedure.attestation_templates_v2.any? || @procedure.feature_enabled?(:attestation_v2)
      helpers.edit_admin_procedure_attestation_template_v2_path(@procedure)
    else
      # pf: routing v1 maintenu pour compatibilité avec procédures existantes
      helpers.edit_admin_procedure_attestation_template_path(@procedure)
    end
  end

  def error_messages
    @procedure.errors.messages_for(:attestation_template).to_sentence
  end
end
