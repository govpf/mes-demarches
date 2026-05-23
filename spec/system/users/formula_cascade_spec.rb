# frozen_string_literal: true

# pf: S1 — Cascade entre formules (A → B → C).
# Vérifie que modifier un champ source déclenche bien le recalcul transitif :
# Montant HT → TTC → TVA. Ce scénario cible les bugs de câblage dans la chaîne
# controller → refresh_formulas_after → compute_formulas_in_order → display,
# pas les calculs arithmétiques eux-mêmes.
describe 'Formula cascade between formulas', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:user) { create(:user, password: password) }

  let!(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      { type: :integer_number, libelle: 'Montant HT' },
      { type: :formule, libelle: 'TTC' },
      { type: :formule, libelle: 'TVA' },
    ])
  end

  let(:user_dossier) { user.dossiers.first }

  let(:montant_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Montant HT' } }
  let(:ttc_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'TTC' } }
  let(:tva_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'TVA' } }

  before do
    ttc_tdc.update!(formule_expression: "{tdc#{montant_tdc.stable_id}} * 1.2")
    tva_tdc.update!(formule_expression: "{tdc#{ttc_tdc.stable_id}} - {tdc#{montant_tdc.stable_id}}")

    log_in(user, procedure)
    fill_individual
  end

  scenario 'le recalcul transitif A→B→C est déclenché par le controller après autosave' do
    find('.dom-ready')

    fill_in('Montant HT', with: '100')
    wait_for_autosave

    # pf: attendre que la cascade soit persistée en DB (recalcul asynchrone possible)
    wait_until { champ_value_for('TTC').present? }
    wait_until { champ_value_for('TVA').present? }

    # TTC = 100 * 1.2 = 120 (peut être "120" ou "120,00" selon le formatage)
    expect(page).to have_text('120')
    # TVA = TTC - Montant = 120 - 100 = 20 (pas d'assertion page-level ici : "20" est
    # une sous-chaîne de "120" et serait vacuoirement vraie ; la vérification DB ci-dessous suffit)

    # Vérification DB pour confirmer que les valeurs sont bien persistées
    ttc_value = champ_value_for('TTC')
    tva_value = champ_value_for('TVA')
    expect(Rational(ttc_value).to_f).to eq(120.0)
    expect(Rational(tva_value).to_f).to eq(20.0)
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
