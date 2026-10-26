# frozen_string_literal: true

class Dossiers::InvalidIneligibiliteRulesComponent < ApplicationComponent
  # pf: backport upstream 3570fe70b3. The alert answers an edit, never a page render:
  # a rendered page shows the deposit button disabled and the footer link opening the
  # alert on demand. It answers the edit of a champ the rule reads, so a rule met
  # through an answer the usager never gave (an untouched checkbox reads « Non »)
  # stays silent until the usager touches what the rule is about.
  def initialize(dossier:, updated_champ: nil, wrapped: true)
    @dossier = dossier
    @updated_champ = updated_champ
    @wrapped = wrapped
  end

  private

  attr_reader :dossier

  def render?
    dossier.revision.ineligibilite_enabled?
  end

  def error_message
    dossier.revision.ineligibilite_message
  end

  def opened?
    !@updated_champ.nil? && rule_reads?(@updated_champ) && !dossier.can_passer_en_construction?
  end

  def rule_reads?(champ)
    dossier.revision.ineligibilite_rules&.sources&.include?(champ.stable_id) || false
  end

  def wrapped? = @wrapped
end
