# frozen_string_literal: true

# pf: formule-ligne qui référence une AUTRE formule-ligne de la même ligne,
# puis agrégat hors bloc (cas du dossier 690725 : Montant réel = MIN(Montant
# théorique, Plafond), Total = SOMME(Montant réel)). Les formules-ligne ne sont
# pas persistées : la formule aval doit recalculer la formule amont à la volée,
# sinon elle lit 0 et le total vaut 0.
describe 'Formule-ligne chaînée dans un bloc répétable', js: true do
  let(:password) { SECURE_PASSWORD }
  let!(:user) { create(:user, password: password) }

  let!(:procedure) do
    create(:procedure, :published, :for_individual, types_de_champ_public: [
      {
        type: :repetition, libelle: 'Cultures', mandatory: false, children: [
          { type: :integer_number, libelle: 'Surface' },
          { type: :formule, libelle: 'Montant théorique' },
          { type: :formule, libelle: 'Montant réel' },
        ],
      },
      { type: :formule, libelle: 'Total' },
    ])
  end

  let!(:user_dossier) { create(:dossier, :brouillon, :with_individual, procedure:, user:) }
  let(:revision) { procedure.active_revision }
  let(:bloc_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Cultures' } }
  let(:surface_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Surface' } }
  let(:theorique_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Montant théorique' } }
  let(:reel_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Montant réel' } }
  let(:total_tdc) { revision.types_de_champ.find { |t| t.libelle == 'Total' } }

  before do
    theorique_tdc.update!(formule_expression: "{tdc#{surface_tdc.stable_id}} * 20")
    reel_tdc.update!(formule_expression: "MIN({tdc#{theorique_tdc.stable_id}}, 1000)")
    total_tdc.update!(formule_expression: "SOMME({tdc#{bloc_tdc.stable_id}/sub_#{reel_tdc.stable_id}})")

    # 2 lignes : surface 30 → réel 600 ; surface 75 → réel 1000 (plafond) ⇒ total 1600
    [30, 75].each do |v|
      row_id = user_dossier.repetition_add_row(bloc_tdc, updated_by: 'setup')
      user_dossier.champ_for_update(surface_tdc, row_id:, updated_by: 'setup').update!(value: v.to_s)
    end
    user_dossier.compute_formulas_in_order

    login_as user, scope: :user
    visit brouillon_dossier_path(user_dossier)
    find('.dom-ready')
  end

  scenario 'la formule aval et le total utilisent la formule amont de chaque ligne' do
    expect(total_value).to eq(1600)

    # 1re ligne : surface 30 → 10 ⇒ théorique 200 ⇒ réel 200 ⇒ total 1200
    within '.repetition .champs-group:first-child' do
      fill_in('Surface', with: '10')
      blur
    end
    wait_for_autosave

    wait_until { total_value == 1200 }
    expect(total_value).to eq(1200)
  end

  private

  # pf: lecture directe en DB — project_champs est mémoïsé.
  def total_value
    Champ.where(dossier_id: user_dossier.id, stable_id: total_tdc.stable_id, row_id: nil)
      .first&.read_attribute(:value).to_i
  end
end
