# frozen_string_literal: true

# pf: S4 — Vérifier que la valeur d'un champ formule de type "string" s'affiche
# en texte brut, sans balise <time>. Bug historique : le sniffer de dates
# appliquait Date.parse sur toute valeur commençant par "\A\d{4}-\d{2}-\d{2}",
# rendant "2026-CAP-19297/288" dans un <time>. La correction consiste à
# n'utiliser format_as_date que quand formule_output_type == 'date'.
describe 'Formula type-aware display', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:user) { create(:user, password: password) }

  let!(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      { type: :date, libelle: "Date d'arrivée" },
      { type: :text, libelle: 'Référence transport' },
      { type: :formule, libelle: 'Identifiant' },
    ])
  end

  let(:user_dossier) { user.dossiers.first }

  let(:date_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == "Date d'arrivée" } }
  let(:ref_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Référence transport' } }
  let(:formula_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Identifiant' } }

  before do
    # pf: utiliser stable_id pour éviter la résolution de libelle qui nécessite
    # un contexte de révision complet — cohérent avec formule_cascade_audit_spec.
    formula_tdc.update!(
      formule_expression: "CONCATENER(\"\", ANNEE({tdc#{date_tdc.stable_id}}), \"-\", {tdc#{ref_tdc.stable_id}})"
    )
    log_in(user, procedure)
    fill_individual
  end

  scenario "la valeur de la formule string n'est pas enveloppée dans une balise <time>" do
    find('.dom-ready')

    fill_in("Date d'arrivée", with: '2026-06-08')
    fill_in('Référence transport', with: 'CAP-19297/288')
    wait_for_autosave

    wait_until { champ_value_for('Identifiant').present? }

    # La valeur calculée doit être visible comme texte brut
    expect(page).to have_text('2026-CAP-19297/288')

    # La valeur ne doit PAS être enveloppée dans un <time> (bug historique du sniffer)
    within(:xpath, "//*[contains(text(), '2026-CAP-19297/288')]/ancestor::*[contains(@class, 'fr-text')][1]") do
      expect(page).not_to have_selector('time')
    end
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
