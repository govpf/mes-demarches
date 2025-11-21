# frozen_string_literal: true

describe LinkedDossierFieldsService do
  let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :text, libelle: 'Nom' }]) }
  let(:dossier) { create(:dossier, :en_construction, procedure: procedure) }

  let(:linked_procedure) { create(:procedure, types_de_champ_public: [{ type: :text, libelle: 'Prénom' }]) }
  let(:linked_dossier) { create(:dossier, :en_construction, procedure: linked_procedure) }

  let(:service) { LinkedDossierFieldsService.new(dossier) }

  describe '#enrich_variables' do
    context 'sans dossier lié' do
      it 'retourne les variables de base inchangées' do
        base_variables = { 'Nom' => 'Carlsen' }
        result = service.enrich_variables(base_variables)

        expect(result).to eq(base_variables)
      end
    end

    context 'avec un dossier lié' do
      let(:procedure) do
        create(:procedure, types_de_champ_public: [
          { type: :text, libelle: 'Nom' },
          { type: :dossier_link, libelle: 'Dossier de candidature' }
        ])
      end

      before do
        linked_dossier.champs.first.update(value: 'Magnus')

        dossier_link_champ = dossier.champs.find { |c| c.is_a?(Champs::DossierLinkChamp) }
        dossier_link_champ.update(value: linked_dossier.id)

        dossier.champs.find { |c| c.libelle == 'Nom' }.update(value: 'Carlsen')
      end

      it 'enrichit avec les variables du dossier lié' do
        base_variables = { 'Nom' => 'Carlsen' }
        result = service.enrich_variables(base_variables)

        expect(result['Nom']).to eq('Carlsen')
        expect(result['Prénom (candidature)']).to eq('Magnus')
        expect(result['Numéro du dossier (candidature)']).to eq(linked_dossier.id.to_s)
      end

      it 'utilise le dernier mot significatif comme suffixe' do
        base_variables = {}
        result = service.enrich_variables(base_variables)

        expect(result.keys).to include('Prénom (candidature)')
        expect(result.keys).to include('Numéro du dossier (candidature)')
      end

      it 'ne suit pas récursivement les liens vers dossiers' do
        # Créer un 3ème dossier lié au 2ème
        third_procedure = create(:procedure, types_de_champ_public: [
          { type: :text, libelle: 'Ville' },
          { type: :dossier_link, libelle: 'Autre dossier' }
        ])
        third_dossier = create(:dossier, :en_construction, procedure: third_procedure)
        third_dossier.champs.first.update(value: 'Amiens')

        # Lier le 3ème au 2ème
        other_link = third_dossier.champs.find { |c| c.is_a?(Champs::DossierLinkChamp) }
        other_link.update(value: linked_dossier.id)

        # Mettre à jour pour pointer vers le 3ème dossier
        dossier_link_champ = dossier.champs.find { |c| c.is_a?(Champs::DossierLinkChamp) }
        dossier_link_champ.update(value: third_dossier.id)

        base_variables = {}
        result = service.enrich_variables(base_variables)

        # On doit avoir les champs du 3ème dossier
        expect(result['Ville (candidature)']).to eq('Amiens')
        # Mais pas ceux du dossier lié au 3ème (pas de récursion)
        expect(result.keys.filter { |k| k.include?('Prénom') }).to be_empty
      end

      it 'ignore les champs DossierLink à l\'intérieur des dossiers liés (profondeur 1 uniquement)' do
        # Dossier lié contient lui-même un DossierLinkChamp
        nested_procedure = create(:procedure, types_de_champ_public: [
          { type: :text, libelle: 'Info' },
          { type: :dossier_link, libelle: 'Dossier imbriqué' }
        ])
        nested_dossier = create(:dossier, :en_construction, procedure: nested_procedure)
        nested_dossier.champs.first.update(value: 'Donnée niveau 1')
        nested_dossier.champs.last.update(value: '999') # Pointe vers un autre dossier

        # Lier au dossier principal
        dossier_link_champ = dossier.champs.find { |c| c.is_a?(Champs::DossierLinkChamp) }
        dossier_link_champ.update(value: nested_dossier.id)

        result = service.enrich_variables({})

        # Vérifier qu'on a bien les données niveau 1
        expect(result['Info (candidature)']).to eq('Donnée niveau 1')
        # Mais pas le champ DossierLink lui-même
        expect(result.keys).not_to include('Dossier imbriqué (candidature)')
        # Et surtout pas de récursion vers le dossier 999
        expect(result.keys.count).to be <= 10 # Pas d'explosion de variables
      end
    end

    context 'avec plusieurs dossiers liés' do
      let(:procedure) do
        create(:procedure, types_de_champ_public: [
          { type: :text, libelle: 'Nom' },
          { type: :dossier_link, libelle: 'Dossier de candidature' },
          { type: :dossier_link, libelle: 'Dossier annuel' }
        ])
      end

      let(:second_linked_procedure) { create(:procedure, types_de_champ_public: [{ type: :text, libelle: 'Année' }]) }
      let(:second_linked_dossier) { create(:dossier, :en_construction, procedure: second_linked_procedure) }

      before do
        linked_dossier.champs.first.update(value: 'Magnus')
        second_linked_dossier.champs.first.update(value: '2024')

        dossier_links = dossier.champs.filter { |c| c.is_a?(Champs::DossierLinkChamp) }
        dossier_links[0].update(value: linked_dossier.id)
        dossier_links[1].update(value: second_linked_dossier.id)
      end

      it 'enrichit avec tous les dossiers liés avec des suffixes différents' do
        base_variables = {}
        result = service.enrich_variables(base_variables)

        expect(result['Prénom (candidature)']).to eq('Magnus')

        expect(result['Année (annuel)']).to eq('2024')
      end
    end
  end

  describe 'robustesse - dossier lié supprimé' do
    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :text, libelle: 'Nom' },
        { type: :dossier_link, libelle: 'Dossier lié' }
      ])
    end

    it 'ignore les dossiers liés qui n\'existent plus' do
      dossier_link_champ = dossier.champs.find { |c| c.is_a?(Champs::DossierLinkChamp) }
      dossier_link_champ.update(value: 99999) # ID inexistant

      result = service.enrich_variables({})

      # Ne doit pas crasher et ne pas inclure de variables du dossier inexistant
      expect(result.keys.filter { |k| k.include?('lié') }).to be_empty
    end
  end

  describe 'sécurité - permissions sur les dossiers liés' do
    let(:instructeur) { create(:instructeur) }
    let(:usager) { create(:user) }

    let(:procedure) do
      create(:procedure, types_de_champ_public: [
        { type: :text, libelle: 'Nom' },
        { type: :dossier_link, libelle: 'Dossier lié' }
      ])
    end

    let(:dossier_accessible) { create(:dossier, :en_construction, procedure: procedure, user: usager) }
    let(:dossier_prive) { create(:dossier, :en_construction, procedure: linked_procedure, user: create(:user)) }

    before do
      # Dossier lié pointé mais appartenant à un autre usager
      dossier_prive.champs.first.update(value: 'Donnée sensible')

      # Lier les dossiers
      dossier_link_champ = dossier_accessible.champs.find { |c| c.is_a?(Champs::DossierLinkChamp) }
      dossier_link_champ.update(value: dossier_prive.id)
    end

    it 'ne révèle pas les données des dossiers d\'un autre usager' do
      service = LinkedDossierFieldsService.new(dossier_accessible, usager)
      result = service.enrich_variables({})

      # Le dossier lié ne devrait pas apparaître car appartient à un autre user
      expect(result.keys.filter { |k| k.include?('lié') }).to be_empty
      expect(result.values).not_to include('Donnée sensible')
    end

    it 'fonctionne sans user (usage interne)' do
      service = LinkedDossierFieldsService.new(dossier_accessible)
      result = service.enrich_variables({})

      # Sans user, tous les dossiers sont accessibles (fallback)
      expect(result.values).to include('Donnée sensible')
    end
  end

  describe '#generate_suffix' do
    it 'prend le dernier mot significatif' do
      suffix = service.send(:generate_suffix, 'Dossier de présentation')
      expect(suffix).to eq('présentation')
    end

    it 'filtre les articles et prépositions' do
      suffix = service.send(:generate_suffix, 'Dossier annuel')
      expect(suffix).to eq('annuel')
    end

    it 'supprime les articles élidés l\' en début de mot' do
      suffix = service.send(:generate_suffix, "Dossier de l'année")
      expect(suffix).to eq('année')
    end

    it 'supprime les articles élidés d\' en début de mot' do
      suffix = service.send(:generate_suffix, "Demande d'agrément")
      expect(suffix).to eq('agrément')
    end

    it 'conserve les apostrophes internes' do
      suffix = service.send(:generate_suffix, "Dossier d'aujourd'hui")
      expect(suffix).to eq("aujourd'hui")
    end

    it 'conserve les apostrophes internes complexes' do
      suffix = service.send(:generate_suffix, "Liste jusqu'aujourd'hui")
      expect(suffix).to eq("jusqu'aujourd'hui")
    end

    it 'supprime les parenthèses et leur contenu' do
      suffix = service.send(:generate_suffix, 'Dossier (version 2025)')
      expect(suffix).to eq('Dossier')
    end

    it 'gère un mot unique' do
      suffix = service.send(:generate_suffix, 'Association')
      expect(suffix).to eq('Association')
    end

    it 'préserve la casse originale' do
      suffix = service.send(:generate_suffix, 'Dossier de Présentation')
      expect(suffix).to eq('Présentation')
    end

    it 'utilise le fallback si tous les mots sont filtrés' do
      suffix = service.send(:generate_suffix, 'De la')
      expect(suffix).to eq('la')
    end

    it 'gère les collisions en utilisant 2 mots' do
      # Premier appel
      suffix1 = service.send(:generate_suffix, 'Dossier de présentation')
      expect(suffix1).to eq('présentation')

      # Deuxième appel avec collision
      suffix2 = service.send(:generate_suffix, 'Document de présentation')
      expect(suffix2).to eq('Document présentation')
    end

    it 'gère plusieurs articles élidés' do
      suffix = service.send(:generate_suffix, "Dossier de l'association d'aujourd'hui")
      expect(suffix).to eq("aujourd'hui")
    end

    it 'gère les chiffres' do
      suffix = service.send(:generate_suffix, 'Dossier 2025')
      expect(suffix).to eq('2025')
    end
  end
end
