# frozen_string_literal: true

require 'system/users/dossier_shared_examples' if Rails.root.join('spec/system/users/dossier_shared_examples.rb').exist?

describe 'Référentiel de Polynésie — Dites-le-nous une fois', js: true do
  let(:password) { SECURE_PASSWORD }
  let(:user) { create(:user, password:) }
  let(:user_dossier) { user.dossiers.first }
  let(:mandatory) { false }
  let(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      { type: :referentiel_de_polynesie, libelle: 'Mes informations', mandatory:, table_id: '24' },
    ])
  end
  let(:dlnuf) { { field_id: 9, field_name: 'Email', field_type: 'email' } }
  let(:scope) { { field_id: 9, value: user.email.downcase } }

  before do
    allow(ReferentielDePolynesie::API).to receive(:dlnuf_config).with('24').and_return(dlnuf)
  end

  scenario 'auto-remplissage quand le titulaire a exactement une ligne' do
    allow(ReferentielDePolynesie::API).to receive(:search_with_data)
      .with('24', anything, drop_down_other: anything, scope:)
      .and_return([{ label: 'Association Manuia', value: '24:7', row_data: { 'Nom' => 'Association Manuia', 'Email' => user.email } }])

    log_in(user, procedure)
    fill_individual

    wait_for_autosave
    wait_until { champ_value_for('Mes informations') == 'Association Manuia' }
  end

  scenario 'aucune ligne, champ optionnel : le champ est masqué (zéro friction)' do
    allow(ReferentielDePolynesie::API).to receive(:search_with_data)
      .with('24', anything, drop_down_other: anything, scope:)
      .and_return([])

    log_in(user, procedure)
    fill_individual

    find('.dom-ready')
    # pf: le champ est visible au rendu (fail-open) puis masqué quand le chargement
    # initial confirme que le périmètre de l'usager est vide
    expect(page).to have_no_selector('.editable-champ-referentiel_de_polynesie', visible: :visible)
    expect(page).to have_selector('.editable-champ-referentiel_de_polynesie', visible: :hidden)
  end

  context 'quand le champ est obligatoire' do
    let(:mandatory) { true }

    scenario 'aucune ligne : le champ reste affiché avec le message, sans écho du mail' do
      allow(ReferentielDePolynesie::API).to receive(:search_with_data)
        .with('24', anything, drop_down_other: anything, scope:)
        .and_return([])

      log_in(user, procedure)
      fill_individual

      # pf: on scope au champ lui-même — le mail du titulaire apparaît légitimement
      # ailleurs sur la page (menu de compte), on vérifie qu'il n'est pas échoé ici
      within('.editable-champ-referentiel_de_polynesie') do
        expect(page).to have_text('Aucune donnée enregistrée à votre nom')
        expect(page).to have_no_text(user.email)
      end
    end
  end

  scenario 'plusieurs lignes : la liste apparaît au focus, sans saisie' do
    allow(ReferentielDePolynesie::API).to receive(:search_with_data)
      .with('24', anything, drop_down_other: anything, scope:)
      .and_return([
        { label: 'Association Manuia', value: '24:7', row_data: { 'Nom' => 'Association Manuia', 'Email' => user.email } },
        { label: 'Association Here', value: '24:8', row_data: { 'Nom' => 'Association Here', 'Email' => user.email } },
      ])

    log_in(user, procedure)
    fill_individual

    find('.dom-ready')
    find_field('Mes informations').click
    find('.fr-menu__item', text: 'Association Here').click
    wait_for_autosave
    wait_until { champ_value_for('Mes informations') == 'Association Here' }
  end

  private

  def log_in(user, procedure)
    login_as user, scope: :user
    visit "/commencer/#{procedure.path}"
    click_on 'Commencer la démarche'
    expect(page).to have_content("Votre identité")
    expect(page).to have_current_path(identite_dossier_path(user_dossier))
  end

  def fill_individual
    fill_in('Prénom', with: 'prenom', visible: true)
    fill_in('Nom', with: 'Nom', visible: true)
    within "#identite-form" do
      click_on 'Continuer'
    end
    expect(page).to have_current_path(brouillon_dossier_path(user_dossier))
  end

  def champ_value_for(libelle)
    champs = user_dossier.reload.project_champs_public
    champs.find { |c| c.libelle == libelle }&.reload&.value
  end
end
