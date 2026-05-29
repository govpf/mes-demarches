# frozen_string_literal: true

describe TypesDeChamp::CommuneDePolynesieTypeDeChamp do
  let(:tdc) { build(:type_de_champ_commune_de_polynesie, libelle: 'Commune') }
  let(:procedure) { build(:procedure) }

  describe '#columns' do
    subject(:columns) { tdc.columns(procedure: procedure) }

    it 'expose la colonne de base' do
      expect(columns[0]).to be_a(Columns::ChampColumn)
      expect(columns[0].label).to eq('Commune')
    end

    it 'expose des JSONPathColumn pour code_postal, ile, archipel' do
      json = columns.filter { _1.is_a?(Columns::JSONPathColumn) }
      expect(json.map(&:jsonpath)).to contain_exactly('$.code_postal', '$.ile', '$.archipel')
    end

    it 'type code_postal = integer, ile/archipel = text' do
      by_path = columns.filter { _1.is_a?(Columns::JSONPathColumn) }.index_by(&:jsonpath)
      expect(by_path['$.code_postal'].type).to eq(:integer)
      expect(by_path['$.ile'].type).to eq(:text)
      expect(by_path['$.archipel'].type).to eq(:text)
    end
  end
end
