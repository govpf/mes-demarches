# frozen_string_literal: true

# pf: S3 — Recalcul après modification de l'identité individuelle.
# Vérifie que refresh_formulas_after est bien déclenché par le controller
# identité (étape G) quand l'usager modifie son prénom/nom.
# Les colonnes sont individual_first_name / individual_last_name
# (cf. FormulaColumnResolver lines 63-66), PAS individual_prenom/individual_nom.
describe 'Formula recompute on identity change', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:user) { create(:user, password: password) }

  let!(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      { type: :formule, libelle: 'Salutation' },
    ])
  end

  let(:user_dossier) { user.dossiers.first }
  let(:formula_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Salutation' } }

  before do
    # pf: les colonnes d'identité individuelle sont référencées par leur nom
    # de colonne symbolique, pas par stable_id (elles ne sont pas des TypeDeChamp).
    formula_tdc.update!(
      formule_expression: "CONCATENER(\"Bonjour \", {individual_first_name}, \" \", {individual_last_name})"
    )
    login_as user, scope: :user
    visit "/commencer/#{procedure.path}"
    click_on 'Commencer la démarche'

    expect(page).to have_content('Votre identité')
    expect(page).to have_current_path(identite_dossier_path(user_dossier))
  end

  scenario 'la formule se recalcule quand le nom change dans le formulaire identité' do
    # Première saisie de l'identité
    fill_in('Prénom', with: 'Jean', visible: true)
    fill_in('Nom', with: 'Dupont', visible: true)
    within '#identite-form' do
      click_on 'Continuer'
    end
    expect(page).to have_current_path(brouillon_dossier_path(user_dossier))

    # La formule doit afficher "Bonjour Jean DUPONT" (le nom est normalisé en majuscules)
    wait_until { champ_value_for('Salutation').present? }
    expect(page).to have_text('Bonjour Jean', normalize_ws: true)
    expect(page).to have_text('DUPONT')

    # Retourner sur la page identité et modifier le nom
    visit identite_dossier_path(user_dossier)
    expect(page).to have_content('Votre identité')

    fill_in('Prénom', with: 'Jean', visible: true)
    fill_in('Nom', with: 'Martin', visible: true)
    within '#identite-form' do
      click_on 'Continuer'
    end
    expect(page).to have_current_path(brouillon_dossier_path(user_dossier))

    # La formule doit maintenant afficher "Bonjour Jean MARTIN" (nom en majuscules)
    wait_until { champ_value_for('Salutation').include?('Martin') || champ_value_for('Salutation').include?('MARTIN') }
    expect(page).to have_text('Bonjour Jean', normalize_ws: true)
    expect(page).to have_text('MARTIN')
  end

  private

  def champ_value_for(libelle)
    champ = user_dossier.reload.project_champs_public.find { |c| c.libelle == libelle }
    champ&.reload&.value
  end
end
