# frozen_string_literal: true

# pf: un bloc répétable en annotation privée n'a une première ligne que s'il est obligatoire,
# et une ligne laissée vide n'apparaît pas dans les attestations.
describe 'Annotations privées : blocs répétables', js: true do
  let!(:instructeur) { create(:instructeur) }
  let!(:procedure) do
    create(:procedure, :published, instructeurs: [instructeur], types_de_champ_private: [
      { type: :repetition, libelle: 'Paiements', mandatory: false, children: [{ type: :text, libelle: 'Référence' }] },
      { type: :repetition, libelle: 'Contrôles', mandatory: true, children: [{ type: :text, libelle: 'Agent' }] },
    ])
  end
  let!(:dossier) { create(:dossier, :en_construction, :with_entreprise, procedure:) }

  def paiements = dossier.reload.project_champs_private.find { _1.libelle == 'Paiements' }
  def paiements_pour_attestation = paiements.type_de_champ.champ_value_for_tag(paiements).to_s

  scenario 'le bloc facultatif démarre sans ligne, le bloc obligatoire avec une ligne' do
    login_as instructeur.user, scope: :user
    visit annotations_privees_instructeur_dossier_path(procedure, dossier)

    expect(page).to have_field('Agent')
    expect(page).not_to have_field('Référence')
    expect(paiements_pour_attestation).to eq('')

    click_on 'Ajouter un élément supplémentaire à « Paiements »'
    fill_in 'Référence', with: 'REF-2026-001'
    expect(page).to have_text('Annotations enregistrées')

    # une seconde ligne ajoutée puis laissée vide ne doit pas produire de ligne dans l'attestation
    click_on 'Ajouter un élément supplémentaire à « Paiements »'
    expect(page).to have_field('Référence', count: 2)

    expect(paiements.row_ids.size).to eq(2)
    expect(paiements_pour_attestation).to include('REF-2026-001')
    expect(paiements_pour_attestation.scan('<tr>').size).to eq(2) # en-tête + la seule ligne remplie
  end
end
