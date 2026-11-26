# frozen_string_literal: true

# pf: une formule hors bloc qui lit une autre formule hors bloc jamais calculée
# (une constante comme un plafond : aucune source ne la déclenche) la lisait vide,
# donc 0. L'instructeur saisit le montant, la formule plafonnée doit suivre.
describe 'Formula reading a constant formula in private annotations', js: true do
  let!(:instructeur) { create(:instructeur) }
  let!(:procedure) do
    create(:procedure, :published, instructeurs: [instructeur], types_de_champ_private: [
      { type: :integer_number, libelle: 'Montant estimé', stable_id: 701 },
      { type: :formule, libelle: 'Plafond', stable_id: 702, formule_expression: '1000000' },
      { type: :formule, libelle: 'Montant plafonné', stable_id: 703, formule_expression: 'MIN({tdc701}, {tdc702})' },
    ])
  end
  let!(:dossier) { create(:dossier, :en_construction, :with_entreprise, procedure: procedure) }

  scenario "le montant plafonné suit la saisie de l'instructeur" do
    login_as instructeur.user, scope: :user

    visit instructeur_dossier_path(procedure, dossier)
    click_on 'Annotations privées'

    fill_in 'Montant estimé', with: '875'
    expect(page).to have_text 'Annotations enregistrées'

    # affichée 875 (et non 0) : le plafond constant est bien lu
    within('.editable-champ', text: 'Montant plafonné') do
      expect(page).to have_text('875')
    end
  end
end
