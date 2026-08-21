# frozen_string_literal: true

describe 'users/dossiers/etablissement', type: :view do
  # pf: SIRET valide au sens de Luhn — la mise en forme passe par
  # IdentifiantEntreprise, qui vérifie la clé de controle.
  let(:etablissement) { create(:etablissement, :with_exercices, siret: "41816609600051") }
  let(:dossier) { create(:dossier, etablissement: etablissement) }
  let(:footer) { view.content_for(:footer) }
  # pf: exposé en `let` (plutôt qu'en dur dans le `before`) pour que les
  # contextes imbriqués puissent le surcharger — `subject! { render }` est
  # déclaré à ce même niveau et s'exécute avant tout `before` d'un contexte
  # imbriqué, un `before` imbriqué qui restuberait :roles arriverait donc
  # trop tard.
  let(:roles) { [] }

  before do
    sign_in dossier.user
    assign(:dossier, dossier)
    allow_any_instance_of(APIEntrepriseToken).to receive(:roles).and_return(roles)
    allow_any_instance_of(APIEntrepriseToken).to receive(:expired?).and_return(false)
  end

  subject! { render }

  it 'affiche les informations de l’établissement' do
    expect(rendered).to have_text("418 166 096 00051")
    expect(rendered).to have_text(etablissement.entreprise_raison_sociale)
  end

  context 'etablissement avec infos non diffusables' do
    # pf: SIRET valide au sens de Luhn — la mise en forme passe par
    # IdentifiantEntreprise, qui vérifie la clé de controle.
    let(:etablissement) { create(:etablissement, :with_exercices, :non_diffusable, siret: "41816609600051") }
    it "affiche uniquement le SIRET si infos non diffusables" do
      expect(rendered).to have_text("418 166 096 00051")
      expect(rendered).not_to have_text(etablissement.entreprise_raison_sociale)
      expect(rendered).not_to have_text(etablissement.entreprise.forme_juridique)
    end
  end

  it 'prépare le footer' do
    expect(footer).to have_selector('footer')
  end

  context 'etablissement avec un numéro Tahiti et un jeton API Entreprise aux rôles complets' do
    # pf: numéro Tahiti complet — can_fetch_*? ne lit que les rôles du jeton,
    # jamais la nature du numéro ; FRENCH_ONLY_JOBS n'est enfilé que pour un
    # SIRET (cf. APIEntrepriseService#perform_later_fetch_jobs), donc aucune
    # de ces pièces n'arrivera jamais pour ce dossier.
    let(:etablissement) { create(:etablissement, :with_exercices, siret: "G33972001") }
    let(:roles) { ['attestation_sociale', 'attestation_fiscale_dgfip', 'bilans_entreprise_bdf'] }

    it "ne promet ni attestation sociale, ni attestation fiscale, ni bilans Banque de France" do
      expect(rendered).to have_text(etablissement.entreprise_raison_sociale)
      expect(rendered).not_to have_text("Une attestation sociale sera jointe à votre dossier")
      expect(rendered).not_to have_text("Une attestation fiscale sera jointe à votre dossier")
      expect(rendered).not_to have_text("Les 3 derniers bilans connus de votre entreprise par la Banque de France")
    end
  end

  context 'etablissement as degraded mode' do
    let(:etablissement) { Etablissement.create!(siret: '003970001') }

    it "affiche une notice avec un lien de vérification vers l'annuaire" do
      expect(rendered).to have_text("#{etablissement.siret.first(6)}-#{etablissement.siret.last(3)}")
      expect(rendered).to have_link("Vérifier dans l’annuaire des entreprises", href: "https://www.ispf.pf/rte/attestation/#{etablissement.siret.first(6)}/#{etablissement.siret.last(3)}")
    end
  end
end
