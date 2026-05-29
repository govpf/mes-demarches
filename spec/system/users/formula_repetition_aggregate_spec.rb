# frozen_string_literal: true

# pf: S5/S6 — Agrégation d'une FORMULE-LIGNE de bloc répétable (chantier
# formule-agrégat). Le bloc contient Prix HT (saisi) + Montant TTC (formule-ligne
# = Prix HT × 2) ; l'agrégat hors bloc somme la formule-ligne :
#   Total = SOMME({Lignes/Montant TTC}).
# On vérifie toute la chaîne UI → controller → refresh_formulas_after →
# (recalcul formule-ligne par ligne) → agrégat → display :
#   - S5 : affichage de l'agrégat pour un dossier pré-rempli
#   - S6 : modifier la valeur source d'une ligne recalcule la formule-ligne
#          PUIS l'agrégat.
#
# pf: ce S6 (agrégat d'une formule-ligne) est aussi le test opérationnel de
# référence pour la refonte « passe accumulante » (cf.
# docs/superpowers/specs/2026-05-28-formule-passe-accumulante-design.md) : il
# doit rester vert quel que soit le mécanisme (recalcul à la volée actuel ou
# accumulateur futur).
#
# pf: lignes pré-remplies via le MODÈLE (déterministe). L'ajout multi-lignes via
# l'UI puis saisie immédiate est une zone de flakiness autosave/Turbo
# pré-existante (course re-render), hors périmètre de ce chantier.
describe 'Formula aggregate over a repetition block', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:user) { create(:user, password: password) }

  let!(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      {
        type: :repetition, libelle: 'Lignes de facture', mandatory: false, children: [
          { type: :integer_number, libelle: 'Prix HT' },
          { type: :formule, libelle: 'Montant TTC' },
        ],
      },
      { type: :formule, libelle: 'Total' },
    ])
  end

  let!(:user_dossier) { create(:dossier, :brouillon, :with_individual, procedure:, user:) }
  let(:revision) { procedure.active_revision }
  let(:bloc_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Lignes de facture' } }
  let(:prix_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Prix HT' } }
  let(:ttc_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Montant TTC' } }
  let(:total_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Total' } }

  before do
    # formule-ligne (intra-ligne) : Montant TTC = Prix HT × 2
    ttc_tdc.update!(formule_expression: "{tdc#{prix_tdc.stable_id}} * 2")
    # agrégat hors bloc : Total = SOMME des Montant TTC de toutes les lignes
    total_tdc.update!(formule_expression: "SOMME({tdc#{bloc_tdc.stable_id}/sub_#{ttc_tdc.stable_id}})")

    # pré-remplir 2 lignes via le modèle : Prix HT 100 et 200
    # → Montant TTC 200 et 400 → Total = 600
    [100, 200].each do |v|
      row_id = user_dossier.repetition_add_row(bloc_tdc, updated_by: 'setup')
      user_dossier.champ_for_update(prix_tdc, row_id:, updated_by: 'setup').update!(value: v.to_s)
    end
    user_dossier.compute_formulas_in_order

    login_as user, scope: :user
    visit brouillon_dossier_path(user_dossier)
    find('.dom-ready')
  end

  scenario 'S5 — l’agrégat somme la formule-ligne de chaque ligne (600)' do
    expect(total_value).to eq(600)
  end

  scenario 'S6 — modifier la source d’une ligne recalcule la formule-ligne puis l’agrégat' do
    expect(total_value).to eq(600)

    # 1re ligne : Prix HT 100 → 150  ⇒ Montant TTC 200 → 300  ⇒ Total 600 → 700
    within '.repetition .champs-group:first-child' do
      fill_in('Prix HT', with: '150')
      blur
    end
    wait_for_autosave

    wait_until { total_value == 700 }
    expect(total_value).to eq(700)
  end

  private

  # pf: lecture directe en DB (read_attribute) — project_champs est mémoïsé et
  # renverrait une valeur périmée dans wait_until.
  def total_value
    Champ.where(dossier_id: user_dossier.id, stable_id: total_tdc.stable_id, row_id: nil)
      .first&.read_attribute(:value).to_i
  end
end
