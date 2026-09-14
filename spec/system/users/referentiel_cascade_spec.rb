# frozen_string_literal: true

# pf: cascade référentiel — un champ referentiel_de_polynesie peut être filtré par un champ
# « pilote » (ici un drop_down_list « Type de produit »). Ce filtre restreint la recherche
# Baserow (rempart n°1, côté controller #search) et bloque le dépôt si la ligne sélectionnée
# ne correspond plus au pilote au moment du submit (rempart n°2, validation modèle). Voir
# ReferentielDePolynesie::ContextualFilter et Champs::ReferentielDePolynesieChamp#referentiel_filter_integrity.
#
# pf: les deux drop_down_list « Type de produit »/« Type ligne » n'ont que 2 options
# (Semences/Plants) et sont obligatoires (pas d'option « Non renseigné ») : avec
# Champs::DropDownListChamp::THRESHOLD_NB_OPTIONS_AS_RADIO = 5, ils sont rendus en boutons
# radio (pas en <select>) — on utilise donc `choose`, pas `select`, cf. spec/system/users/dropdown_spec.rb.
describe 'Référentiel de Polynésie — cascade (filtre contextuel)', js: true do
  let(:password) { SECURE_PASSWORD }
  let(:user) { create(:user, password:) }
  let(:user_dossier) { user.dossiers.first }
  let(:referentiel) { create(:baserow_referentiel) } # baserow://24
  let(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'], mandatory: true },
      { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel:, mandatory: true },
      {
        type: :repetition, libelle: 'Lignes', mandatory: false, children: [
          { type: :drop_down_list, libelle: 'Type ligne', options: ['Semences', 'Plants'] },
          { type: :referentiel_de_polynesie, libelle: 'Produit ligne', referentiel: },
        ],
      },
    ])
  end
  let(:revision) { procedure.active_revision }
  let(:pilot_tdc) { revision.types_de_champ_public[0] }
  let(:rdp_tdc) { revision.types_de_champ_public[1] }
  let(:repetition_tdc) { revision.types_de_champ_public[2] }
  let(:line_pilot_tdc) { revision.children_of(repetition_tdc).first }
  let(:line_rdp_tdc) { revision.children_of(repetition_tdc).second }
  let(:fields) { { 12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 100, value: 'Semences' }, { id: 101, value: 'Plants' }] } } }
  let(:semences_scope) { [{ field_id: 12, type: 'single_select_equal', value: 100 }] }
  let(:plants_scope) { [{ field_id: 12, type: 'single_select_equal', value: 101 }] }
  let(:semences) { [{ label: 'Blé', value: '24:1', row_data: { 'Nom' => 'Blé', 'Catégorie' => 'Semences' } }] }
  let(:plants) { [{ label: 'Rosier', value: '24:2', row_data: { 'Nom' => 'Rosier', 'Catégorie' => 'Plants' } }] }

  before do
    [rdp_tdc, line_rdp_tdc].zip([pilot_tdc, line_pilot_tdc]).each do |rdp, pilot|
      rdp.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot.stable_id}" })
    end
    allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).and_return(nil)
    allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(fields)
    allow(ReferentielDePolynesie::API).to receive(:search_with_data).with('24', anything, drop_down_other: anything, scopes: semences_scope).and_return(semences)
    allow(ReferentielDePolynesie::API).to receive(:search_with_data).with('24', anything, drop_down_other: anything, scopes: plants_scope).and_return(plants)
  end

  scenario 'le pilote restreint la liste, le changer ne vide pas la sélection mais bloque le dépôt' do
    log_in(user, procedure)
    fill_individual

    find('.dom-ready')
    within('.editable-champ-referentiel_de_polynesie', match: :first) do
      expect(page).to have_text('Renseignez d’abord « Type de produit »')
    end

    choose 'Semences', allow_label_click: true
    wait_for_autosave

    find_field('Produit', match: :first).click
    expect(page).to have_css('.fr-menu__item', text: 'Blé')
    expect(page).to have_no_css('.fr-menu__item', text: 'Rosier')
    find('.fr-menu__item', text: 'Blé').click
    wait_for_autosave
    wait_until { champ_value_for('Produit') == 'Blé' }

    choose 'Plants', allow_label_click: true
    wait_for_autosave
    # pf: non-destructif — la sélection reste
    expect(champ_value_for('Produit')).to eq('Blé')

    click_on 'Déposer le dossier'
    expect(page).to have_text('ne correspond pas à « Plants »')
    expect(user_dossier.reload).to be_brouillon

    choose 'Semences', allow_label_click: true
    wait_for_autosave
    click_on 'Déposer le dossier'
    expect(page).to have_current_path(merci_dossier_path(user_dossier))
  end

  scenario 'dans un bloc répétable, chaque ligne suit son propre pilote' do
    log_in(user, procedure)
    fill_individual
    choose 'Semences', allow_label_click: true
    wait_for_autosave

    click_on 'Ajouter un élément supplémentaire à « Lignes »'
    wait_for_autosave
    click_on 'Ajouter un élément supplémentaire à « Lignes »'
    wait_for_autosave

    rows = page.all('.repetition .champs-group', minimum: 2)
    within(rows[0]) do
      choose 'Semences', allow_label_click: true
    end
    wait_for_autosave
    within(rows[1]) do
      choose 'Plants', allow_label_click: true
    end
    wait_for_autosave

    # pf: la liste de suggestions react-aria est rendue dans un portail (#rac-portal), hors du
    # bloc répétable : on ouvre le combobox dans la ligne, mais on assert au niveau de la page.
    within(rows[0]) { find_field('Produit ligne').click }
    expect(page).to have_css('.fr-menu__item', text: 'Blé')
    expect(page).to have_no_css('.fr-menu__item', text: 'Rosier')
    find('.fr-menu__item', text: 'Blé').click
    wait_for_autosave

    within(rows[1]) { find_field('Produit ligne').click }
    expect(page).to have_css('.fr-menu__item', text: 'Rosier')
    expect(page).to have_no_css('.fr-menu__item', text: 'Blé')
  end

  private

  def log_in(user, procedure)
    login_as user, scope: :user
    visit "/commencer/#{procedure.path}"
    click_on 'Commencer la démarche'
    expect(page).to have_content('Votre identité')
    expect(page).to have_current_path(identite_dossier_path(user_dossier))
  end

  def fill_individual
    fill_in('Prénom', with: 'prenom', visible: true)
    fill_in('Nom', with: 'Nom', visible: true)
    within '#identite-form' do
      click_on 'Continuer'
    end
    expect(page).to have_current_path(brouillon_dossier_path(user_dossier))
  end

  def champ_value_for(libelle)
    user_dossier.reload.project_champs_public.find { _1.libelle == libelle }&.reload&.value
  end
end
