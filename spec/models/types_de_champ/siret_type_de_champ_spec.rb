# frozen_string_literal: true

describe TypesDeChamp::SiretTypeDeChamp do
  let(:tdc_siret) { build(:type_de_champ_siret, libelle: 'Numéro SIRET') }
  let(:procedure) { build(:procedure) }

  describe "#columns" do
    subject(:columns) { tdc_siret.columns(procedure: procedure) }

    it "returns base column without duplicating SIRET when already in libelle" do
      expect(columns[0].label).to eq("Numéro SIRET")
    end

    it "returns base column with SIRET when libelle doesn't contain SIRET" do
      tdc_siret.update(libelle: "Identification de l'entreprise")

      expect(columns[0].label).to eq("Identification de l'entreprise – SIRET")
    end

    it "does not include jsonpath SIRET column" do
      expect(columns.find { |c| c.is_a?(Columns::JSONPathColumn) && c.jsonpath == "$.siret" }).to be_nil
    end

    it "includes required etablissement jsonpaths" do
      expected_paths = [
        "$.entreprise_raison_sociale",
        "$.entreprise_siren",
        "$.entreprise_nom_commercial",
        "$.entreprise_forme_juridique",
        "$.entreprise_date_creation",
        "$.libelle_naf",
      ]

      json_columns = columns.filter { _1.is_a?(Columns::JSONPathColumn) }
      expect(json_columns.map(&:jsonpath)).to include(*expected_paths)
    end

    it "does not include address columns (not filled for Numéro Tahiti)" do
      address_columns = columns.filter { _1.is_a?(Columns::JSONPathColumn) && _1.jsonpath.match?(/postal_code|city_name|department_code|region_name/) }

      expect(address_columns).to be_empty
    end
  end
end
