# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TypesDeChamp::ReferentielFilterValidator do
  let(:referentiel) { create(:baserow_referentiel) }
  let(:procedure) do
    create(:procedure, types_de_champ_public: [
      { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
      { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
    ])
  end
  let(:revision) { procedure.draft_revision }
  let(:pilot_tdc) { revision.types_de_champ_public.first }
  let(:rdp_tdc) { revision.types_de_champ_public.second }

  subject { procedure.validate(:types_de_champ_public_editor) }

  def configure_filter(pilot_column_id)
    rdp_tdc.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => pilot_column_id })
    procedure.reload
  end

  it 'accepte un pilote admissible' do
    configure_filter("type_de_champ/#{pilot_tdc.stable_id}")
    expect { subject }.not_to change { procedure.errors.count }
  end

  it 'signale un pilote supprimé, en nommant le référentiel' do
    configure_filter("type_de_champ/#{pilot_tdc.stable_id}")
    revision.remove_type_de_champ(pilot_tdc.stable_id)
    procedure.reload
    subject
    error = procedure.errors.find { _1.type == :invalid_referentiel_filter } || procedure.errors.first
    expect(procedure.errors[:draft_types_de_champ_public].join).to include('supprimé, déplacé')
    expect(error.options[:type_de_champ]).to eq(rdp_tdc)
  end

  it 'signale un pilote déplacé après le référentiel' do
    configure_filter("type_de_champ/#{pilot_tdc.stable_id}")
    revision.move_type_de_champ(pilot_tdc.stable_id, 1)
    procedure.reload
    expect { subject }.to change { procedure.errors.count }.by(1)
  end

  it 'signale un pilote changé en un type non filtrable' do
    configure_filter("type_de_champ/#{pilot_tdc.stable_id}")
    pilot_tdc.update!(type_champ: TypeDeChamp.type_champs.fetch(:date))
    procedure.reload
    expect { subject }.to change { procedure.errors.count }.by(1)
  end

  it 'ignore les référentiels sans filtre' do
    expect { subject }.not_to change { procedure.errors.count }
  end
end
