# frozen_string_literal: true

# pf: vérifie que les sous-champs des types PF (DN, commune) sont exposés
# comme colonnes filtrables côté instructeur — bénéfice direct de la
# normalisation value_json + JSONPathColumn.
describe 'Procedure#form_filterable_columns avec sous-champs PF' do
  context 'Numéro DN' do
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :numero_dn, libelle: 'DN' }]) }

    it 'expose la date de naissance comme colonne filtrable' do
      labels = procedure.form_filterable_columns.map(&:label)
      expect(labels).to include('DN – Date de naissance')
    end
  end

  context 'Commune de Polynésie' do
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :commune_de_polynesie, libelle: 'Commune' }]) }

    it 'expose ile, code postal et archipel comme colonnes filtrables' do
      labels = procedure.form_filterable_columns.map(&:label)
      expect(labels).to include('Commune – Ile', 'Commune – Code postal', 'Commune – Archipel')
    end
  end
end
