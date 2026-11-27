# frozen_string_literal: true

describe FormulaReferences do
  describe '.scan' do
    it 'reconnaît les quatre formes de référence' do
      refs = described_class.scan('{tdc12} + {tdc34/code_postal} + SOMME({tdc56/sub_78}) + { dossier_number }')
      expect(refs.map(&:to_h)).to eq([
        { raw: 'tdc12', stable_id: 12, sub_stable_id: nil, path: nil },
        { raw: 'tdc34/code_postal', stable_id: 34, sub_stable_id: nil, path: 'code_postal' },
        { raw: 'tdc56/sub_78', stable_id: 56, sub_stable_id: 78, path: nil },
        { raw: 'dossier_number', stable_id: nil, sub_stable_id: nil, path: nil },
      ])
    end

    it 'ne reconnaît pas le format hérité {123} comme une référence de champ' do
      expect(described_class.scan('{123}').first.stable_id).to be_nil
    end

    it 'renvoie [] pour nil et pour une expression sans accolades' do
      expect(described_class.scan(nil)).to eq([])
      expect(described_class.scan('1 + 1')).to eq([])
    end
  end

  it '.stable_ids dédoublonne et trie, sans les sous-champs' do
    expect(described_class.stable_ids('{tdc9} * {tdc3} + {tdc9/sub_4}')).to eq([3, 9])
  end

  it '.gsub remplace chaque référence par le résultat du bloc' do
    out = described_class.gsub('{tdc1} + {dossier_number}') { |ref, match| ref.champ? ? 'X' : match }
    expect(out).to eq('X + {dossier_number}')
  end
end
