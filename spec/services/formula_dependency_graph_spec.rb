# frozen_string_literal: true

# pf: graphe de dépendances des formules d'une révision (ordre de calcul,
# arêtes, fermeture aval, cycle, référence vers l'avant).
describe FormulaDependencyGraph do
  let!(:procedure) do
    create(:procedure, :published,
           types_de_champ_public: [
             { type: :integer_number, libelle: 'A' },
             { type: :formule, libelle: 'F' },
             {
               type: :repetition, libelle: 'B', children: [
                 { type: :formule, libelle: 'L' },
                 { type: :integer_number, libelle: 'P' },
               ],
             },
             { type: :formule, libelle: 'T' },
           ],
           types_de_champ_private: [
             { type: :formule, libelle: 'G' },
             { type: :integer_number, libelle: 'N' },
             {
               type: :repetition, libelle: 'BP', children: [
                 { type: :formule, libelle: 'LP' },
               ],
             },
           ])
  end

  # Types de champ lus sur une instance de révision jetable, pour que la
  # révision du graphe ne soit chargée qu'après l'écriture des expressions.
  let(:tdcs) { Procedure.find(procedure.id).published_revision.types_de_champ.index_by(&:libelle) }
  let(:champ_a) { tdcs.fetch('A') }
  let(:formule_f) { tdcs.fetch('F') }
  let(:bloc_b) { tdcs.fetch('B') }
  let(:ligne_l) { tdcs.fetch('L') }
  let(:nombre_p) { tdcs.fetch('P') }
  let(:formule_t) { tdcs.fetch('T') }
  let(:formule_g) { tdcs.fetch('G') }
  let(:nombre_n) { tdcs.fetch('N') }
  let(:ligne_lp) { tdcs.fetch('LP') }

  let(:graph) { Procedure.find(procedure.id).active_revision.formula_graph }

  def ref(tdc) = "{tdc#{tdc.stable_id}}"
  def sub_ref(bloc, tdc) = "{tdc#{bloc.stable_id}/sub_#{tdc.stable_id}}"
  def ids(*tdcs) = tdcs.map(&:stable_id)

  before do
    formule_f.update!(formule_expression: "#{ref(champ_a)} * 2")
    ligne_l.update!(formule_expression: "#{ref(formule_f)} * 10")
    formule_t.update!(formule_expression: "SOMME(#{sub_ref(bloc_b, ligne_l)}) + NB(#{ref(bloc_b)})")
    formule_g.update!(formule_expression: "#{ref(formule_f)} + 1")
    ligne_lp.update!(formule_expression: "SOMME(#{sub_ref(bloc_b, ligne_l)})")
  end

  it "calcule le public déplié puis le privé" do
    expect(graph.formula_stable_ids).to eq(ids(formule_f, ligne_l, formule_t, formule_g, ligne_lp))
  end

  it 'classe les nœuds par niveau' do
    expect(graph.node(formule_f.stable_id).level).to eq(:public)
    expect(graph.node(formule_g.stable_id).level).to eq(:private)
    expect(graph.node(ligne_l.stable_id)).to have_attributes(level: :row, bloc_stable_id: bloc_b.stable_id)
    expect(graph.node(champ_a.stable_id)).to be_nil
  end

  it 'distingue les trois sortes de dépendance' do
    expect(graph.edges(formule_g.stable_id).map(&:to_h)).to eq([{ kind: :champ, stable_id: formule_f.stable_id, sub_stable_id: nil }])
    expect(graph.edges(formule_t.stable_id).map(&:to_h)).to eq([
      { kind: :sub_champ, stable_id: bloc_b.stable_id, sub_stable_id: ligne_l.stable_id },
      { kind: :bloc, stable_id: bloc_b.stable_id, sub_stable_id: nil },
    ])
  end

  it 'expose les types de champ formule dans l’ordre de calcul' do
    expect(graph.any_formula?).to be true
    expect(graph.formula_types_de_champ.map(&:stable_id)).to eq(ids(formule_f, ligne_l, formule_t, formule_g, ligne_lp))
    expect(graph.formula_types_de_champ(only: ids(ligne_lp, formule_f)).map(&:stable_id)).to eq(ids(formule_f, ligne_lp))
  end

  it "suit l'aval, bloc parent d'une formule-ligne compris" do
    expect(graph.downstream_of([champ_a.stable_id])).to eq(ids(formule_f, ligne_l, formule_t, formule_g, ligne_lp))
  end

  it "part du bloc parent quand la source est un sous-champ" do
    expect(graph.downstream_of([nombre_p.stable_id])).to eq(ids(formule_t, ligne_lp))
  end

  it "ne renvoie rien pour une source sans aval" do
    expect(graph.downstream_of([nombre_n.stable_id])).to eq([])
  end

  it "ne renvoie une graine formule que si le parcours la ré-atteint" do
    expect(graph.downstream_of([formule_f.stable_id])).to eq(ids(ligne_l, formule_t, formule_g, ligne_lp))
  end

  it "ajoute l'aval des formules à drapeau" do
    formule_f.update!(formule_expression: 'ANNEE(AUJOURDHUI())')
    fresh = Procedure.find(procedure.id).active_revision.formula_graph
    expect(fresh.flagged('has_clock')).to eq([formule_f.stable_id])
    expect(fresh.flagged_with_downstream('has_clock')).to eq(ids(formule_f, ligne_l, formule_t, formule_g, ligne_lp))
    expect(fresh.flagged_with_downstream('has_clock', private_only: true)).to eq([])
  end

  it 'détecte une auto-référence et un cycle indirect' do
    expect(graph.circular_reference?(formule_f.stable_id, "#{ref(formule_f)} + 1")).to be true
    expect(graph.circular_reference?(formule_f.stable_id, "#{ref(formule_g)} + 1")).to be true
    expect(graph.circular_reference?(formule_g.stable_id, "#{ref(formule_f)} + 1")).to be false
    expect(graph.circular_reference?(nil, "#{ref(formule_f)} + 1")).to be false
  end

  it "détecte une référence vers l'avant" do
    expect(graph.forward_reference?(formule_f.stable_id, ref(formule_t))).to be true
    expect(graph.forward_reference?(ligne_l.stable_id, ref(formule_f))).to be false
    expect(graph.forward_reference?(nil, ref(formule_t))).to be false
  end

  it 'accepte une formule sans expression' do # focus 2
    formule_f.update_column(:options, formule_f.options.merge('formule_expression' => nil))
    fresh = Procedure.find(procedure.id).active_revision.formula_graph
    expect(fresh.formula_stable_ids).to include(formule_f.stable_id)
    expect(fresh.edges(formule_f.stable_id)).to eq([])
  end

  it "tolère une référence vers un champ absent de la révision" do # focus 3
    expect(graph.downstream_of([999_999])).to eq([])
    expect(graph.forward_reference?(formule_f.stable_id, '{tdc999999}')).to be true
    expect(graph.circular_reference?(formule_f.stable_id, '{tdc999999}')).to be false
    expect(graph.edges(999_999)).to eq([])
  end

  it "atteint une formule-ligne privée depuis un sous-champ de bloc public" do # focus 4
    expect(graph.downstream_of([nombre_p.stable_id])).to include(ligne_lp.stable_id)
    expect(graph.formula_stable_ids.index(ligne_lp.stable_id)).to be > graph.formula_stable_ids.index(formule_t.stable_id)
  end

  it "reconstruit le graphe à chaque appel, même sur une révision publiée" do # focus 1
    published = procedure.active_revision
    expect(published.formula_graph).not_to equal(published.formula_graph)
  end

  it "sert un graphe à jour à un dossier chargé après la modification d'une expression" do # focus 1
    procedure.active_revision.formula_graph
    formule_g.update!(formule_expression: "#{ref(champ_a)} + 1")
    dossier = Dossier.find(create(:dossier, procedure:).id)
    expect(dossier.revision.formula_graph.edges(formule_g.stable_id).map(&:stable_id)).to eq([champ_a.stable_id])
  end

  it 'renvoie un graphe vide pour une révision sans formule' do
    revision = create(:procedure, types_de_champ_public: [{ type: :integer_number }]).draft_revision
    expect(revision.formula_graph.any_formula?).to be false
    expect(revision.formula_graph.downstream_of([1])).to eq([])
  end
end
