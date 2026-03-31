# frozen_string_literal: true

class AddDefaultFalseToAttestationTemplatesKind < ActiveRecord::Migration[7.2]
  def up
    # pf: backfill kind before adding constraint — upstream relies on a maintenance task
    # between releases, but we integrate multiple releases at once so the task never runs
    safety_assured { execute("UPDATE attestation_templates SET kind = 'acceptation' WHERE kind IS NULL") }
    add_check_constraint :attestation_templates, "kind IS NOT NULL", name: "attestation_templates_kind_null", validate: false
  end

  def down
    remove_check_constraint :attestation_templates, name: "attestation_templates_kind_null"
  end
end
