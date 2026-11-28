# frozen_string_literal: true

# pf: caractérise la règle « quelles colonnes une formule peut référencer ».
describe FormulaReferenceScope do
  let(:procedure) do
    create(:procedure,
           types_de_champ_public: [
             { type: :integer_number, libelle: 'A' },
             { type: :formule, libelle: 'F1' },
             {
               type: :repetition, libelle: 'Bloc', children: [
                 { type: :integer_number, libelle: 'P' },
                 { type: :formule, libelle: 'L' },
               ],
             },
             { type: :formule, libelle: 'F2' },
           ],
           types_de_champ_private: [
             { type: :integer_number, libelle: 'N' },
             { type: :formule, libelle: 'G' },
           ])
  end
  let(:revision) { procedure.draft_revision }

  def tdc(libelle) = revision.types_de_champ.find { _1.libelle == libelle }
  def scope_of(libelle) = described_class.new(revision.coordinate_for(tdc(libelle)))
  def ids(*libelles) = Set.new(libelles.map { tdc(_1).stable_id })

  describe '#allowed_stable_ids' do
    it 'formule publique : champs publics précédents et blocs précédents' do
      expect(scope_of('F2').allowed_stable_ids).to eq(ids('A', 'F1', 'P', 'L', 'Bloc'))
    end

    it 'première formule publique : rien après elle' do
      expect(scope_of('F1').allowed_stable_ids).to eq(ids('A'))
    end

    it 'formule-ligne : frères précédents de la ligne et racine avant le bloc' do
      expect(scope_of('L').allowed_stable_ids).to eq(ids('P', 'A', 'F1'))
    end

    it 'annotation privée : tout le public, les annotations précédentes, les blocs publics' do
      expect(scope_of('G').allowed_stable_ids).to eq(ids('A', 'F1', 'P', 'L', 'F2', 'N', 'Bloc'))
    end
  end

  it 'renvoie un périmètre vide pour un champ non formule' do
    expect(scope_of('A').columns).to eq([])
  end

  it 'les délégations de la coordonnée renvoient le même résultat' do
    coordinate = revision.coordinate_for(tdc('F2'))
    scope = described_class.new(coordinate)
    expect(coordinate.available_columns_for_formula).to eq(scope.columns)
    expect(coordinate.available_parent_columns_for_formula).to eq(scope.parent_columns)
    expect(coordinate.aggregable_repetition_types_de_champ).to eq(scope.aggregable_repetitions)
  end
end
