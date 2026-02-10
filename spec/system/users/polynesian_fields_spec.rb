# frozen_string_literal: true

describe 'Polynesian Fields - Nationalités, Commune, Code Postal & Numéro DN PF', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:user) { create(:user, password: password) }

  let!(:procedure_with_pf_fields) do
    create(:procedure, :published, :for_individual, no_gender: false, types_de_champ_public: [
      { type: :nationalites, libelle: 'Nationalité', mandatory: true },
      { type: :commune_de_polynesie, libelle: 'Commune de Polynésie', mandatory: true },
      { type: :code_postal_de_polynesie, libelle: 'Code postal de Polynésie', mandatory: true }
    ])
  end

  let!(:procedure_with_te_fenua) do
    create(:procedure, :published, :for_individual, no_gender: false, types_de_champ_public: [
      { type: :te_fenua, libelle: 'Carte TeFenua', mandatory: false, options: { te_fenua_layer: 'marker' } }
    ])
  end

  let!(:procedure_with_numero_dn) do
    create(:procedure, :published, :for_individual, no_gender: false, types_de_champ_public: [
      { type: :numero_dn, libelle: 'Numéro DN', mandatory: true }
    ])
  end

  let(:user_dossier) { user.dossiers.first }

  scenario 'user fills and submits dossier with PF fields' do
    log_in(user, procedure_with_pf_fields)
    fill_individual

    find('.dom-ready')

    select('Australienne', from: form_id_for('Nationalité'))
    wait_for_autosave

    select('Mahina - Tahiti - 98709', from: form_id_for('Commune de Polynésie'))
    wait_for_autosave

    select('98709 - Mahina - Tahiti', from: form_id_for('Code postal de Polynésie'))
    wait_for_autosave

    wait_until { champ_value_for('Nationalité').present? }
    expect(champ_value_for('Nationalité')).to eq('Australienne')

    wait_until { champ_value_for('Commune de Polynésie').present? }
    expect(champ_value_for('Commune de Polynésie')).to eq('Mahina - Tahiti - 98709')

    wait_until { champ_value_for('Code postal de Polynésie').present? }
    expect(champ_value_for('Code postal de Polynésie')).to eq('98709 - Mahina - Tahiti')

    expect(page).to have_selected_value('Nationalité', selected: 'Australienne')
    expect(page).to have_selected_value('Commune de Polynésie', selected: 'Mahina - Tahiti - 98709')
    expect(page).to have_selected_value('Code postal de Polynésie', selected: '98709 - Mahina - Tahiti')

    click_on 'Déposer le dossier'

    expect(page).to have_current_path(merci_dossier_path(user_dossier))
    expect(user_dossier.reload.en_construction?).to be true
  end

  scenario 'PF fields are required' do
    log_in(user, procedure_with_pf_fields)
    fill_individual

    click_on 'Déposer le dossier'

    expect(user_dossier.reload.brouillon?).to be true
    expect(page).to have_current_path(brouillon_dossier_path(user_dossier))

    expect(page).to have_selector("#sumup-errors")
  end

  scenario 'user fills and submits dossier with Numero DN field', vcr: { cassette_name: 'numero_dn_check', allow_playback_repeats: true } do
    log_in(user, procedure_with_numero_dn)
    fill_individual

    find('.dom-ready')

    expect(page).to have_content('Numéro DN')
    expect(page).to have_css('.numero-dn')

    fill_in('DN', with: '2106223')
    fill_in('Date de naissance', with: '1983-11-28')
    wait_for_autosave

    wait_until { champ_for('Numéro DN').numero_dn.present? }
    expect(champ_for('Numéro DN').numero_dn).to eq('2106223')

    expect(page).to have_field('DN', with: '2106223')
    expect(page).to have_field('Date de naissance', with: '1983-11-28')

    click_on 'Déposer le dossier'

    expect(page).to have_current_path(merci_dossier_path(user_dossier))
    expect(user_dossier.reload.en_construction?).to be true
  end

  scenario 'user interacts with TeFenua field', vcr: true do
    log_in(user, procedure_with_te_fenua)
    fill_individual

    find('.dom-ready')

    expect(page).to have_content('Carte TeFenua')
    expect(page).to have_css('.te-fenua')

    expect(page).to have_css('.te-fenua[data-initialized="true"]', wait: 10)

    expect(page).to have_css('.ol-control')

    click_on 'Déposer le dossier'

    expect(page).to have_current_path(merci_dossier_path(user_dossier))
    expect(user_dossier.reload.en_construction?).to be true
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
    find('label', text: 'Monsieur').click
    fill_in('Prénom', with: 'Jean', visible: true)
    fill_in('Nom', with: 'Dupont', visible: true)
    within "#identite-form" do
      click_on 'Continuer'
    end
    expect(page).to have_current_path(brouillon_dossier_path(user_dossier))
  end

  def champ_value_for(libelle)
    champ_for(libelle).value
  end

  def champ_for(libelle)
    champs = user_dossier.reload.project_champs_public
    champ = champs.find { |c| c.libelle == libelle }
    champ.reload
  end
end
