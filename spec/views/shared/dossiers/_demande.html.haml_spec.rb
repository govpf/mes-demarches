# frozen_string_literal: true

describe 'shared/dossiers/demande', type: :view do
  include EtablissementHelper

  let(:current_instructeur) { create(:instructeur) }
  let(:individual) { nil }
  let(:etablissement) { nil }
  let(:procedure) { create(:procedure, :published) }
  let(:dossier) { create(:dossier, :en_construction, procedure: procedure, etablissement: etablissement, individual: individual) }

  before do
    sign_in(current_instructeur.user)
  end

  subject { render 'shared/dossiers/demande', dossier: dossier, demande_seen_at: nil, profile: 'usager' }

  context 'when dossier was created by an etablissement' do
    let(:etablissement) { create(:etablissement) }

    it 'renders the etablissement infos' do
      expect(subject).to include(etablissement.entreprise_raison_sociale)
      expect(subject).to include(pretty_siret(etablissement.entreprise_siret_siege_social))
      expect(subject).to include(etablissement.entreprise_forme_juridique)
    end

    context 'and entreprise is an association' do
      let(:etablissement) { create(:etablissement, :is_association) }

      it 'renders the association infos' do
        expect(subject).to include(etablissement.association_rna)
        expect(subject).to include(etablissement.association_titre)
        expect(subject).to include(etablissement.association_objet)
      end
    end
  end

  context 'when dossier was created by an individual' do
    let(:individual) { build(:individual) }

    it 'renders the individual identity infos' do
      expect(subject).to include(individual.gender)
      expect(subject).to include(individual.nom)
      expect(subject).to include(individual.prenom)
      expect(subject).to include(I18n.l(individual.birthdate, format: :long))
    end
  end

  context 'when the dossier has champs' do
    let(:procedure) { create(:procedure, :published, :with_type_de_champ) }

    it 'renders the champs' do
      dossier.project_champs_public.each do |champ|
        expect(subject).to include(champ.libelle)
      end
    end
  end

  context 'when a champ is freshly build' do
    let(:procedure) { create(:procedure, :published, :with_type_de_champ) }
    before do
      dossier.project_champs_public.first.destroy
    end

    it 'renders without error' do
      procedure.active_revision.types_de_champ.each do |tdc|
        expect(subject).to include(tdc.libelle)
      end
    end
  end

  # pf: les lignes de routage du partial lisaient `@profile`, une variable
  # d'instance qu'aucun controleur n'assigne, au lieu du local `profile` recu en
  # `locals:`. La branche usager etait donc toujours fausse et
  # IdentiteEntrepriseForUsagerComponent — qui porte le masquage — jamais rendu.
  context 'quand l’entreprise a exerce son droit a la non publication' do
    let(:etablissement) { create(:etablissement, :non_diffusable) }

    it 'masque les informations pour l’usager' do
      expect(subject).to include('a exercé son droit à la non publication')
      expect(subject).not_to include(etablissement.entreprise_forme_juridique)
    end
  end

  context 'quand le profil est instructeur' do
    let(:etablissement) { create(:etablissement, :non_diffusable) }

    subject { render 'shared/dossiers/demande', dossier: dossier, demande_seen_at: nil, profile: 'instructeur' }

    it 'affiche les informations, le masquage ne concerne pas l’instruction' do
      expect(subject).to include(etablissement.entreprise_forme_juridique)
    end
  end

  # pf: l'ISPF ne renseigne pas diffusable_commercialement — les etablissements
  # Tahiti sont tous a nil. Une simple verification de veracite les masquerait
  # tous ; seule une opposition explicite doit masquer.
  context 'quand diffusable_commercialement n’est pas renseigne (cas Tahiti)' do
    let(:etablissement) { create(:etablissement, diffusable_commercialement: nil) }

    it 'affiche les informations a l’usager' do
      expect(subject).to include(etablissement.entreprise_raison_sociale)
      expect(subject).not_to include('a exercé son droit à la non publication')
    end
  end

  context 'quand l’entreprise est explicitement diffusable' do
    let(:etablissement) { create(:etablissement, diffusable_commercialement: true) }

    it 'affiche les informations a l’usager' do
      expect(subject).to include(etablissement.entreprise_raison_sociale)
    end
  end
end
