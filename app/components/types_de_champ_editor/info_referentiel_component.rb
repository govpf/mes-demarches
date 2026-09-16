# frozen_string_literal: true

class TypesDeChampEditor::InfoReferentielComponent < ApplicationComponent
  attr_reader :procedure, :type_de_champ
  delegate :referentiel, to: :type_de_champ
  delegate :ready?, to: :referentiel, allow_nil: true

  def initialize(procedure:, type_de_champ:)
    @procedure = procedure
    @type_de_champ = type_de_champ
  end

  def edit_referentiel_on_draft_or_clone_url
    if new_referentiel_required?
      new_referentiel_url
    else
      edit_existing_referentiel_url
    end
  end

  # pf: cascade — rappel du filtre configuré, lu depuis les options du champ : le nom de la
  # colonne Baserow est celui mis en cache à l’enregistrement, la colonne pilote est résolue
  # localement. Aucun appel Baserow ne doit partir à l’affichage de l’éditeur de champs.
  def referentiel_filter_summary
    return nil if !type_de_champ.referentiel_filter?

    config = Hash(type_de_champ.referentiel_filter)
    pilot_libelle = pilot_column_label(config['pilot_column_id'].to_s)

    "Lignes restreintes selon « #{pilot_libelle} » (colonne « #{config['baserow_field_name']} »)"
  end

  private

  # pf: repli sur l’identifiant brut si la colonne pilote a disparu de la révision de travail
  def pilot_column_label(column_id)
    procedure.find_column(h_id: { procedure_id: procedure.id, column_id: }).label
  rescue ActiveRecord::RecordNotFound
    column_id
  end

  def new_referentiel_url
    dup_options = referentiel ? { referentiel_id: referentiel.id } : {}
    new_admin_procedure_referentiel_path(procedure, type_de_champ.stable_id, dup_options)
  end

  def edit_existing_referentiel_url
    edit_admin_procedure_referentiel_path(procedure, type_de_champ.stable_id, type_de_champ.referentiel)
  end

  def new_referentiel_required?
    referentiel.nil? || procedure.publiee? || referentiel_used_in_published_procedure?
  end

  def referentiel_used_in_published_procedure?
    @procedure.published_revision&.types_de_champ&.any? { _1.referentiel_id == referentiel.id }
  end
end
