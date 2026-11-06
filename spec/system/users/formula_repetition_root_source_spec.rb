# frozen_string_literal: true

# pf: formule-ligne qui lit une formule RACINE, puis agrégat hors bloc :
#   Taux = Coef × 2 (racine), Montant = Prix × Taux (ligne), Total = SOMME(Montant).
# Modifier Coef (hors bloc) doit recalculer le Total : l'agrégat dépend du bloc,
# pas de la formule-ligne, et la cascade doit suivre le bloc parent de la
# formule-ligne atteinte (Champ#dependent_formula_stable_ids).
describe 'Agrégat d’une formule-ligne dépendant d’une formule racine', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:user) { create(:user, password: password) }

  let!(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      { type: :integer_number, libelle: 'Coef' },
      { type: :formule, libelle: 'Taux' },
      {
        type: :repetition, libelle: 'Lignes', mandatory: false, children: [
          { type: :integer_number, libelle: 'Prix' },
          { type: :formule, libelle: 'Montant' },
        ],
      },
      { type: :formule, libelle: 'Total' },
    ])
  end

  let!(:user_dossier) { create(:dossier, :brouillon, :with_individual, procedure:, user:) }
  let(:revision) { procedure.active_revision }
  let(:coef_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Coef' } }
  let(:taux_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Taux' } }
  let(:bloc_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Lignes' } }
  let(:prix_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Prix' } }
  let(:montant_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Montant' } }
  let(:total_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Total' } }

  before do
    taux_tdc.update!(formule_expression: "{tdc#{coef_tdc.stable_id}} * 2")
    montant_tdc.update!(formule_expression: "{tdc#{prix_tdc.stable_id}} * {tdc#{taux_tdc.stable_id}}")
    total_tdc.update!(formule_expression: "SOMME({tdc#{bloc_tdc.stable_id}/sub_#{montant_tdc.stable_id}})")

    # Coef 5 ⇒ Taux 10 ; lignes Prix 3 et 4 ⇒ Montants 30 et 40 ⇒ Total 70
    user_dossier.champ_for_update(coef_tdc, row_id: nil, updated_by: 'setup').update!(value: '5')
    [3, 4].each do |v|
      row_id = user_dossier.repetition_add_row(bloc_tdc, updated_by: 'setup')
      user_dossier.champ_for_update(prix_tdc, row_id:, updated_by: 'setup').update!(value: v.to_s)
    end
    user_dossier.compute_formulas_in_order

    login_as user, scope: :user
    visit brouillon_dossier_path(user_dossier)
    find('.dom-ready')
  end

  scenario 'modifier la source de la formule racine recalcule le total' do
    expect(total_value).to eq(70)

    # Coef 5 → 10 ⇒ Taux 20 ⇒ Montants 60 et 80 ⇒ Total 140
    fill_in('Coef', with: '10')
    blur
    wait_for_autosave

    wait_until { total_value == 140 }
    expect(total_value).to eq(140)
  end

  private

  # pf: lecture directe en DB — project_champs est mémoïsé.
  def total_value
    Champ.where(dossier_id: user_dossier.id, stable_id: total_tdc.stable_id, row_id: nil)
      .first&.read_attribute(:value).to_i
  end
end
