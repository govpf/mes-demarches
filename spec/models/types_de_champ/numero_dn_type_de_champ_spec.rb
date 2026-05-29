# frozen_string_literal: true

describe TypesDeChamp::NumeroDnTypeDeChamp do
  let(:tdc_dn) { build(:type_de_champ_numero_dn, libelle: 'Numéro DN') }
  let(:procedure) { build(:procedure) }

  describe '#columns' do
    subject(:columns) { tdc_dn.columns(procedure: procedure) }

    it 'expose la colonne de base (le numéro DN)' do
      expect(columns[0]).to be_a(Columns::ChampColumn)
      expect(columns[0].label).to eq('Numéro DN')
    end

    it 'expose une JSONPathColumn pour la date de naissance (type date)' do
      ddn = columns.find { _1.is_a?(Columns::JSONPathColumn) && _1.jsonpath == '$.date_de_naissance' }
      expect(ddn).not_to be_nil
      expect(ddn.type).to eq(:date)
      expect(ddn.label).to eq('Numéro DN – Date de naissance')
    end
  end
end
