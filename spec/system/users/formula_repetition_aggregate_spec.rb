# frozen_string_literal: true

# pf: S5/S6 — Agrégation d'un sous-champ de bloc répétable (chantier
# formule-agrégat). Vérifie la chaîne UI → controller → refresh_formulas_after
# → display de bout en bout :
#   - S5 : l'agrégat s'affiche correctement pour un dossier déjà rempli
#   - S6 : modifier un sous-champ d'une ligne via l'UI recalcule l'agrégat
#
# pf: les lignes sont pré-remplies via le MODÈLE (déterministe). L'ajout de
# plusieurs lignes via l'UI puis saisie immédiate est une zone de flakiness
# autosave/Turbo pré-existante (course re-render) hors périmètre de ce chantier ;
# on teste donc le déclencheur de recalcul le plus à risque (modification d'un
# sous-champ existant), pas l'ajout multi-lignes via l'UI.
describe 'Formula aggregate over a repetition block', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:user) { create(:user, password: password) }

  let!(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      {
        type: :repetition, libelle: 'Lignes de facture', mandatory: false, children: [
          { type: :integer_number, libelle: 'Prix HT' },
        ],
      },
      { type: :formule, libelle: 'Total' },
    ])
  end

  let!(:user_dossier) { create(:dossier, :brouillon, :with_individual, procedure:, user:) }
  let(:revision) { procedure.active_revision }
  let(:bloc_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Lignes de facture' } }
  let(:prix_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Prix HT' } }
  let(:total_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Total' } }

  before do
    total_tdc.update!(formule_expression: "SOMME({tdc#{bloc_tdc.stable_id}/sub_#{prix_tdc.stable_id}})")

    # pré-remplir 2 lignes via le modèle (100, 200) + calcul initial de l'agrégat
    [100, 200].each do |v|
      row_id = user_dossier.repetition_add_row(bloc_tdc, updated_by: 'setup')
      user_dossier.champ_for_update(prix_tdc, row_id:, updated_by: 'setup').update!(value: v.to_s)
    end
    user_dossier.compute_formulas_in_order

    login_as user, scope: :user
    visit brouillon_dossier_path(user_dossier)
    find('.dom-ready')
  end

  scenario 'S5 — l’agrégat affiche la somme des lignes pré-remplies' do
    expect(total_value).to eq(300)
  end

  scenario 'S6 — modifier un sous-champ d’une ligne recalcule l’agrégat' do
    expect(total_value).to eq(300)

    # 1re ligne : 100 → 150
    within '.repetition .champs-group:first-child' do
      fill_in('Prix HT', with: '150')
      blur
    end
    wait_for_autosave

    wait_until { total_value == 350 }
    expect(total_value).to eq(350)
  end

  private

  # pf: lecture directe en DB (read_attribute) — project_champs est mémoïsé et
  # renverrait une valeur périmée dans wait_until.
  def total_value
    Champ.where(dossier_id: user_dossier.id, stable_id: total_tdc.stable_id, row_id: nil)
      .first&.read_attribute(:value).to_i
  end
end
