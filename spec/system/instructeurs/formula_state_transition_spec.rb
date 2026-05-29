# frozen_string_literal: true

# pf: S2 — Recalcul d'une formule lors de la transition d'état "Passer en instruction".
# Vérifie que refresh_formulas_after (ou compute_initial_formulas) est déclenché
# après la transition, de sorte que la formule JOURS_ENTRE({dossier_en_instruction_at},
# AUJOURDHUI()) vaut 0 le jour même de la mise en instruction.
describe 'Formula recompute on state transition to en_instruction', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:instructeur) { create(:instructeur, password: password) }
  let!(:procedure) do
    create(:procedure, :published, instructeurs: [instructeur], types_de_champ_public: [
      { type: :formule, libelle: 'Jours en instruction' },
    ])
  end
  let!(:dossier) { create(:dossier, :en_construction, :with_entreprise, procedure: procedure) }
  let(:formula_tdc) { procedure.active_revision.types_de_champ_public.find { |t| t.libelle == 'Jours en instruction' } }

  before do
    formula_tdc.update!(formule_expression: 'JOURS_ENTRE({dossier_en_instruction_at}, AUJOURDHUI())')
  end

  scenario "la formule vaut 0 le jour de la mise en instruction" do
    login_as instructeur.user, scope: :user
    visit instructeur_procedure_path(procedure)

    click_on dossier.user.email
    click_on 'Passer en instruction'
    expect(page).to have_text('Dossier passé en instruction.')

    dossier.reload
    expect(dossier.state).to eq(Dossier.states.fetch(:en_instruction))

    # La formule doit afficher 0 (passée en instruction aujourd'hui)
    # et non "—" (FORMULA_NOT_COMPUTED_MARKER)
    formula_champ = dossier.project_champs_public.find { |c| c.libelle == 'Jours en instruction' }
    expect(formula_champ.value).to eq('0')
    expect(formula_champ.value).not_to eq('—')
    expect(formula_champ.value).not_to be_nil
  end
end
