# frozen_string_literal: true

describe FormulaAiPromptService do
  describe '#generate' do
    let(:type_de_champ) { build(:type_de_champ_formule, formule_output_type: output_type) }
    let(:coordinate) { instance_double(ProcedureRevisionTypeDeChamp) }
    let(:output_type) { 'number' }

    before do
      allow(coordinate).to receive(:available_columns_for_formula).and_return([])
      allow(coordinate).to receive(:revision).and_return(double(types_de_champ: []))
      allow(coordinate).to receive(:child?).and_return(false)
    end

    subject { described_class.new(type_de_champ: type_de_champ, coordinate: coordinate).generate }

    it 'documents the new *_ENTRE date functions' do
      expect(subject).to include('JOURS_ENTRE')
      expect(subject).to include('SEMAINES_ENTRE')
      expect(subject).to include('MOIS_ENTRE')
      expect(subject).to include('ANNEES_ENTRE')
    end

    it 'documents CONTIENT et les listes de choix multiples' do
      expect(subject).to include('CONTIENT(liste, valeur)')
      expect(subject).to include('CONTIENT({Moyens de transport}, "Bus")')
      # pf: le prompt doit dissuader explicitement des deux pièges (== et CHERCHE)
      expect(subject).to match(/N’utilise JAMAIS `==` ni `CHERCHE`/)
    end

    it 'documents the new rounding functions' do
      expect(subject).to include('ARRONDI_INF')
      expect(subject).to include('ARRONDI_SUP')
      expect(subject).to include('ENTIER')
    end

    it 'documents DUREE_SEMAINES' do
      expect(subject).to include('DUREE_SEMAINES')
    end

    it 'documents l’agrégation sur blocs répétables et les nouvelles fonctions' do
      expect(subject).to include('Agrégation sur blocs répétables')
      expect(subject).to include('SOMME({Lignes de facture/Prix HT})')
      expect(subject).to include('NB({Lignes de facture})')
      expect(subject).to include('JOINDRE')
      expect(subject).to include('MEDIANE')
      # la formule-agrégat doit être placée APRÈS le bloc
      expect(subject).to match(/APRÈS le bloc/)
      # plus de mention "agrégat impossible"
      expect(subject).not_to include('Aucun agrégat global n’est possible')
    end

    context 'when output_type is "date"' do
      let(:output_type) { 'date' }

      it 'labels the expected return type as "date"' do
        expect(subject).to match(/Type de résultat attendu.*\*\*date\*\*/m)
      end
    end

    context 'when output_type is "datetime"' do
      let(:output_type) { 'datetime' }

      it 'labels the expected return type as a date+heure' do
        expect(subject).to match(/Type de résultat attendu.*date.*heure/mi)
      end
    end
  end
end
