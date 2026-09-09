# frozen_string_literal: true

describe 'instructeurs/dossiers/print', type: :view do
  before { view.extend DossierHelper }

  context "with a dossier" do
    let(:current_instructeur) { create(:instructeur) }
    let(:dossier) { create(:dossier, :en_instruction, :with_commentaires) }

    before do
      assign(:dossier, dossier)
      allow(view).to receive(:current_instructeur).and_return(current_instructeur)

      render
    end

    it do
      expect(rendered).to include("Dossier n° #{dossier.id}")
      expect(rendered).to include(dossier.procedure.libelle)
    end
  end

  context "with a dossier having an établissement" do
    # pf: verrouille la convergence sur Dossiers::IdentiteEntrepriseComponent — avant cette
    # tâche, l'impression rendait l'ancienne vue avec un libellé « Numéro TAHITI » en dur, en
    # désaccord avec la page demande qui affiche déjà le libellé surchargé par
    # config/custom_locales. Si l'impression rebifurque vers un libellé en dur, ou si la
    # surcharge disparaît, ce test échoue.
    let(:current_instructeur) { create(:instructeur) }
    let(:dossier) { create(:dossier, :en_instruction, :with_entreprise) }

    before do
      assign(:dossier, dossier)
      allow(view).to receive(:current_instructeur).and_return(current_instructeur)

      render
    end

    it "displays the overridden PF label instead of a hardcoded one" do
      expect(rendered).to include("Numéro Tahiti ou SIRET")
      expect(rendered).not_to include("Numéro TAHITI")
    end
  end
end
