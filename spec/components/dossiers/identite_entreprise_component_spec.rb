# frozen_string_literal: true

RSpec.describe Dossiers::IdentiteEntrepriseComponent, type: :component do
  subject { render_inline(described_class.new(etablissement:)) }

  context 'with bilans bdf v2' do
    let(:bilans) { JSON.parse(File.read('spec/fixtures/files/api_entreprise/bilans_entreprise_bdf_v2.json')) }
    let(:etablissement) do
      create(:etablissement,
        entreprise_bilans_bdf: bilans['bilans'],
        entreprise_bilans_bdf_monnaie: bilans['monnaie'])
    end

    it 'renders the excédent brut d’exploitation from the flat v2 payload' do
      expect(subject.to_html).to include("Excédent brut d'exploitation")
      expect(subject.to_html).to include("-1 876 863 k€")
    end
  end

  context 'with bilans bdf v3' do
    let(:bilans) { JSON.parse(File.read('spec/fixtures/files/api_entreprise/bilans_entreprise_bdf.json')) }
    let(:etablissement) do
      create(:etablissement,
        entreprise_bilans_bdf: bilans['data'],
        entreprise_bilans_bdf_monnaie: 'euros')
    end

    it 'renders the excédent brut d’exploitation from the nested v3 payload' do
      expect(subject.to_html).to include("Excédent brut d'exploitation")
      expect(subject.to_html).to include("9 001")
    end
  end

  context 'siret siège social' do
    # pf: SIRET valide au sens de Luhn — la mise en forme passe par
    # IdentifiantEntreprise, qui vérifie la clé de contrôle.
    let(:etablissement) { create(:etablissement, siret: "41816609600051", entreprise_siret_siege_social: siret_siege_social) }

    context 'when siège social has the same siret' do
      let(:siret_siege_social) { "41816609600051" }

      it 'does not duplicate the siret' do
        expect(subject.to_html.scan("418 166 096 00051").size).to eq(1)
      end
    end

    context 'when siège social has a different siret' do
      # pf: également un SIRET valide au sens de Luhn, distinct du précédent
      let(:siret_siege_social) { "44011762001530" }

      it 'shows both sirets' do
        expect(subject.to_html).to include("418 166 096 00051")
        expect(subject.to_html).to include("Numéro Tahiti ou SIRET du siège social")
        expect(subject.to_html).to include("440 117 620 01530")
      end
    end

    context 'when siège social has no siret' do
      let(:siret_siege_social) { nil }

      it 'does not show the siège social row' do
        expect(subject.to_html).not_to include("Numéro Tahiti ou SIRET du siège social")
      end
    end
  end

  context 'when the établissement is not diffusable commercialement' do
    # pf: contrairement à Dossiers::IdentiteEntrepriseForUsagerComponent (qui
    # masque les informations pour l'usager), ce composant est réservé au
    # profil instructeur (cf. app/views/shared/dossiers/_demande.html.haml) :
    # les informations non diffusables restent visibles des instructeurs par
    # conception, cf. le libellé warning_for_private_info. Le composant ne
    # doit donc PAS masquer la raison sociale ici.
    let(:etablissement) { create(:etablissement, :non_diffusable) }

    it 'still shows the raison sociale to the instructeur' do
      expect(subject.to_html).to include(etablissement.entreprise_raison_sociale)
    end
  end
end
