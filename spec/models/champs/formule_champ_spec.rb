# frozen_string_literal: true

describe Champs::FormuleChamp do
  let(:type_de_champ) { build(:type_de_champ_formule, formule_expression: expression) }
  let(:champ) { Champs::FormuleChamp.new(dossier: build(:dossier)) }

  before do
    allow(champ).to receive(:type_de_champ).and_return(type_de_champ)
  end

  describe '#value (stored via before_validation)' do
    context 'with simple expression' do
      let(:expression) { '1 + 1' }

      it 'returns the computed value after validation' do
        champ.validate
        expect(champ.value).to eq('2')
      end
    end

    context 'with unsupported function' do
      let(:expression) { 'CONCAT({Prénom}, " ", {Nom})' }

      it 'returns error message for unsupported functions' do
        champ.validate
        expect(champ.value).to include('Erreur')
      end
    end

    context 'with blank expression' do
      let(:expression) { '' }

      it 'returns nil (no computation)' do
        expect(champ.value).to be_nil
      end
    end

    context 'with nil expression' do
      let(:expression) { nil }

      it 'returns nil (no computation)' do
        expect(champ.value).to be_nil
      end
    end
  end

  describe '#blank?' do
    context 'with computed value' do
      let(:expression) { '1 + 1' }

      it 'is not blank' do
        expect(champ).not_to be_blank
      end
    end

    context 'with no expression' do
      let(:expression) { '' }

      it 'is blank' do
        expect(champ).to be_blank
      end
    end
  end

  describe '#search_terms' do
    let(:expression) { '1 + 1' }

    it 'returns an array with the stored value' do
      champ.validate
      expect(champ.search_terms).to eq(['2'])
    end
  end

  describe '#to_s' do
    let(:expression) { '1 + 1' }

    it 'returns the computed value as string' do
      expect(champ.to_s).to eq(champ.value.to_s)
    end
  end

  describe 'validation' do
    let(:test_champ) { Champs::FormuleChamp.new(dossier: build(:dossier)) }

    before do
      allow(test_champ).to receive(:type_de_champ).and_return(type_de_champ)
    end

    context 'with expression and computed value' do
      let(:expression) { '1 + 1' }

      it 'is valid' do
        expect(test_champ).to be_valid
      end
    end

    context 'with no expression' do
      let(:expression) { '' }

      it 'is valid' do
        expect(test_champ).to be_valid
      end
    end
  end

  describe 'before_validation callback' do
    let(:expression) { '2 + 2' }

    it 'has the callback defined' do
      expect(Champs::FormuleChamp._validation_callbacks.map(&:filter)).to include(:store_computed_value)
    end
  end

  # pf: garde contre les champs formule persistés orphelins (TDC supprimé de
  # la révision mais Champ encore en BDD — cas typique d'un dossier de preview).
  describe 'store_computed_value with persisted orphan champ' do
    let(:expression) { '1 + 1' }
    let(:test_champ) { Champs::FormuleChamp.new(dossier: build(:dossier)) }

    before do
      allow(test_champ).to receive(:type_de_champ).and_return(type_de_champ)
      allow(test_champ).to receive(:persisted?).and_return(true)
      # Simule un orphelin : le stable_id n'est pas dans la révision courante.
      allow(test_champ).to receive(:in_dossier_revision?).and_return(false)
    end

    it 'does not crash and does not compute anything' do
      expect { test_champ.validate }.not_to raise_error
      expect(test_champ.value).to be_nil
    end
  end

  # pf: contre-épreuve — un champ non persisté (construit en mémoire) doit
  # continuer à calculer, même s'il n'est pas dans la révision du dossier.
  describe 'store_computed_value with non-persisted champ' do
    let(:expression) { '3 + 4' }
    let(:test_champ) { Champs::FormuleChamp.new(dossier: build(:dossier)) }

    before do
      allow(test_champ).to receive(:type_de_champ).and_return(type_de_champ)
      allow(test_champ).to receive(:in_dossier_revision?).and_return(false)
    end

    it 'computes normally (guard only targets persisted orphans)' do
      test_champ.validate
      expect(test_champ.value).to eq('7')
    end
  end

  describe '#compute_value_from_formula' do
    let(:dossier) { build(:dossier) }
    let(:formule_champ) { Champs::FormuleChamp.new(dossier: dossier) }

    before do
      allow(formule_champ).to receive(:type_de_champ).and_return(build(:type_de_champ_formule, formule_expression: expression))
    end

    context 'with simple arithmetic' do
      let(:expression) { '2 + 2' }

      it 'computes the result' do
        expect(formule_champ.compute_value_from_formula).to eq('4')
      end
    end

    context 'when expression is blank' do
      let(:expression) { '' }

      it 'returns empty string' do
        expect(formule_champ.compute_value_from_formula).to eq('')
      end
    end

    context 'with invalid reference' do
      let(:expression) { '{Inexistant}' }

      before do
        allow(dossier).to receive(:champs).and_return([formule_champ])
      end

      it 'returns error message' do
        expect(formule_champ.compute_value_from_formula).to include('Erreur')
      end
    end
  end
end
