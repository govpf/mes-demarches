# frozen_string_literal: true

# pf: Spec sentinelle — Dentaku 3.5.4 supporte SUM/COUNT/MAX/MIN/AVG sur
# des arrays passés en binding (non documenté officiellement). Le chantier
# « formules-agrégat sur blocs répétables » repose sur ce comportement.
#
# Si Dentaku change ce comportement à une upgrade future, cette spec rouge
# avant que la résolution des formules-agrégat ne casse en prod.

require 'dentaku'

describe 'Dentaku — fonctions d\'agrégation sur arrays bindings' do
  let(:calculator) { Dentaku::Calculator.new }

  describe 'SUM' do
    it 'somme les éléments d\'un array' do
      expect(calculator.evaluate!('SUM(arr)', arr: [1, 2, 3])).to eq(6)
    end

    it 'retourne 0 sur un array vide' do
      expect(calculator.evaluate!('SUM(arr)', arr: [])).to eq(0)
    end

    it 'supporte les decimals' do
      expect(calculator.evaluate!('SUM(arr)', arr: [1.5, 2.5, 3.0])).to eq(7.0)
    end
  end

  describe 'COUNT' do
    it 'retourne la taille d\'un array' do
      expect(calculator.evaluate!('COUNT(arr)', arr: [1, 2, 3])).to eq(3)
    end

    it 'retourne 0 sur un array vide' do
      expect(calculator.evaluate!('COUNT(arr)', arr: [])).to eq(0)
    end
  end

  describe 'MAX' do
    it 'retourne le maximum d\'un array' do
      expect(calculator.evaluate!('MAX(arr)', arr: [10, 30, 20])).to eq(30)
    end

    it 'retourne nil sur un array vide' do
      expect(calculator.evaluate!('MAX(arr)', arr: [])).to be_nil
    end
  end

  describe 'MIN' do
    it 'retourne le minimum d\'un array' do
      expect(calculator.evaluate!('MIN(arr)', arr: [10, 30, 20])).to eq(10)
    end
  end

  describe 'AVG' do
    it 'retourne la moyenne d\'un array' do
      expect(calculator.evaluate!('AVG(arr)', arr: [10, 20, 30])).to eq(20)
    end
  end

  describe 'combinaisons' do
    it 'permet l\'arithmétique entre agrégats de plusieurs arrays' do
      result = calculator.evaluate!('SUM(a) - SUM(b)', a: [100, 200, 50], b: [150])
      expect(result).to eq(200)
    end
  end

  describe 'cas limites' do
    it 'gère un array avec un seul élément' do
      expect(calculator.evaluate!('SUM(arr)', arr: [42])).to eq(42)
      expect(calculator.evaluate!('COUNT(arr)', arr: [42])).to eq(1)
      expect(calculator.evaluate!('MAX(arr)', arr: [42])).to eq(42)
    end
  end
end
