# frozen_string_literal: true

require 'rails_helper'

# pf: cascade — la configuration du filtre contextuel vit dans le panneau « préremplir et
# afficher » du wizard « Configurer le champ », plus dans la carte du champ.
RSpec.describe Referentiels::ReferentielFilterComponent, type: :component do
  let(:referentiel) { create(:baserow_referentiel) } # baserow://24
  let(:procedure) do
    create(:procedure, types_de_champ_public: [
      { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
      { type: :date, libelle: 'Date' },
      { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
    ])
  end
  let(:pilot_tdc) { procedure.draft_revision.types_de_champ_public.first }
  let(:type_de_champ) { procedure.draft_revision.types_de_champ_public.third }
  let(:fields) do
    {
      1 => { name: 'Nom', type: 'text', select_options: [] },
      12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 100, value: 'Semences' }] },
      20 => { name: 'Fichier', type: 'file', select_options: [] },
    }
  end
  let(:component) { described_class.new(procedure:, type_de_champ:, referentiel:) }

  before { allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(fields) }

  subject { render_inline(component) }

  it 'affiche la case décochée et les deux listes masquées par défaut' do
    subject
    expect(page).to have_text('Indiquez si les lignes proposées doivent être restreintes selon un champ du formulaire')
    expect(page).to have_unchecked_field('Restreindre les lignes proposées')
    expect(page).to have_css('[data-hide-target-target="toHide"].fr-hidden')
    expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', with_options: ['Nom', 'Catégorie'])
    expect(page).not_to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', with_options: ['Fichier'])
    expect(page).to have_select('type_de_champ[referentiel_filter_form][pilot_column_id]', with_options: ['Type de produit'])
    expect(page).not_to have_select('type_de_champ[referentiel_filter_form][pilot_column_id]', with_options: ['Date'])
  end

  it 'affiche la case cochée et les listes visibles quand un filtre est configuré' do
    type_de_champ.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}" })
    subject
    expect(page).to have_checked_field('Restreindre les lignes proposées')
    expect(page).to have_css('[data-hide-target-target="toHide"]:not(.fr-hidden)')
    expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', selected: 'Catégorie')
    expect(page).to have_select('type_de_champ[referentiel_filter_form][pilot_column_id]', selected: 'Type de produit')
  end

  it 'garde la colonne en cache et prévient quand Baserow est injoignable' do
    allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(nil)
    type_de_champ.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}" })
    subject
    expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', selected: 'Catégorie')
    expect(page).to have_text('Colonnes indisponibles pour le moment')
  end

  context 'pour un référentiel upstream (API)' do
    let(:referentiel) { create(:api_referentiel, :exact_match) }
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :referentiel, referentiel: }]) }
    let(:type_de_champ) { procedure.draft_revision.types_de_champ_public.first }

    it 'ne rend rien' do
      expect(subject.to_html).to be_empty
    end
  end
end
