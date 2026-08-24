# frozen_string_literal: true

# pf: CONTIENT sur un champ à choix multiple. Vérifie la chaîne complète
# usager → controller → refresh_formulas_after → compute → affichage, en
# cochant ET en décochant (la décoche est le sens qui casse le plus souvent :
# le champ repasse à nil et la formule doit repasser à false).
# Couvre aussi la non-régression métier qui motive CONTIENT : cocher
# « Bus scolaire » ne doit PAS satisfaire un test sur l'option « Bus »
# (ce que CHERCHE, en recherche de sous-chaîne, faisait à tort).
describe 'Formula CONTIENT on a multiple choice champ', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:user) { create(:user, password: password) }

  let!(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      { type: :multiple_drop_down_list, libelle: 'Moyens de transport', options: ['Vélo', 'Bus', 'Bus scolaire'] },
      { type: :formule, libelle: 'Mode' },
    ])
  end

  let(:user_dossier) { user.dossiers.first }

  let(:moyens_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Moyens de transport' } }
  let(:mode_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Mode' } }

  before do
    mode_tdc.update!(
      formule_expression: "SI(CONTIENT({tdc#{moyens_tdc.stable_id}}, \"Bus\"), \"Transport en commun\", \"Autre\")"
    )

    log_in(user, procedure)
    fill_individual
  end

  scenario 'la formule se recalcule quand l\'usager coche puis décoche une option' do
    find('.dom-ready')

    # 1. Une option dont le libellé CONTIENT « Bus » ne satisfait pas le test
    check('Bus scolaire', exact: true, allow_label_click: true)
    wait_for_autosave
    wait_until { champ_value_for('Mode') == 'Autre' }
    expect(champ_value_for('Moyens de transport')).to eq('["Bus scolaire"]')

    # 2. Cocher l'option exacte déclenche le recalcul
    check('Bus', exact: true, allow_label_click: true)
    wait_for_autosave
    wait_until { champ_value_for('Mode') == 'Transport en commun' }
    expect(page).to have_text('Transport en commun')

    # 3. Décocher repasse la formule à false
    uncheck('Bus', exact: true, allow_label_click: true)
    wait_for_autosave
    wait_until { champ_value_for('Mode') == 'Autre' }
    expect(champ_value_for('Moyens de transport')).to eq('["Bus scolaire"]')
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
    fill_in('Prénom', with: 'Jean', visible: true)
    fill_in('Nom', with: 'Test', visible: true)
    within '#identite-form' do
      click_on 'Continuer'
    end
    expect(page).to have_current_path(brouillon_dossier_path(user_dossier))
  end

  def champ_value_for(libelle)
    champ = user_dossier.reload.project_champs_public.find { |c| c.libelle == libelle }
    champ&.reload&.value
  end
end
