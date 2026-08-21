# frozen_string_literal: true

describe IdentifiantEntreprise do
  describe '.parse — table de vérité' do
    # saisie => [nature, valide?, erreur]
    # nature ∈ :tahiti_partiel, :tahiti_complet, :siret, :inconnu
    {
      # --- Tahiti partiel : 6 à 8 caractères, plusieurs établissements possibles
      'G33972'         => [:tahiti_partiel, true,  nil],
      '002253'         => [:tahiti_partiel, true,  nil],
      'G339720'        => [:tahiti_partiel, true,  nil],
      'G3397200'       => [:tahiti_partiel, true,  nil],
      # --- Tahiti complet : 9 caractères, un seul établissement
      'G33972001'      => [:tahiti_complet, true,  nil],
      '002253001'      => [:tahiti_complet, true,  nil],
      # --- SIRET : 14 chiffres, Luhn vérifié
      '41816609600051' => [:siret,          true,  nil],
      '13000582000019' => [:siret,          true,  nil],
      '35600000018723' => [:siret,          true,  nil], # La Poste, Luhn contourné
      '41816609600052' => [:inconnu,        false, :checksum],
      # --- longueurs invalides
      '12345'          => [:inconnu,        false, :length], # 5 car.
      '1234567890'     => [:inconnu,        false, :length], # 10 car.
      '1234567890123'  => [:inconnu,        false, :length], # 13 car.
      '123456789012345' => [:inconnu,       false, :length], # 15 car.
      # --- contenu invalide
      'A1B1C6D9E0F0G1' => [:inconnu,        false, :length], # 14 car. avec lettres
      'abcdef'         => [:inconnu,        false, :length],
      ''               => [:inconnu,        false, :length],
      nil              => [:inconnu,        false, :length],
    }.each do |saisie, (nature, valide, erreur)|
      context "avec #{saisie.inspect}" do
        subject { described_class.parse(saisie) }

        it "est de nature #{nature}" do
          expect(subject.tahiti_partiel?).to eq(nature == :tahiti_partiel)
          expect(subject.tahiti_complet?).to eq(nature == :tahiti_complet)
          expect(subject.siret?).to eq(nature == :siret)
          expect(subject.valide?).to eq(valide)
          expect(subject.erreur).to eq(erreur)
        end
      end
    end
  end

  describe 'normalisation' do
    it 'retire espaces et tirets et met en capitales' do
      expect(described_class.parse('g33972-001').valeur).to eq('G33972001')
      expect(described_class.parse(' 418 166 096 00051 ').valeur).to eq('41816609600051')
    end

    it 'traite nil sans lever' do
      expect(described_class.parse(nil).valeur).to eq('')
    end
  end

  describe '#tahiti?' do
    it do
      expect(described_class.parse('G33972')).to be_tahiti
      expect(described_class.parse('G33972001')).to be_tahiti
      expect(described_class.parse('41816609600051')).not_to be_tahiti
    end
  end

  describe '#source et #adapter_klass' do
    it 'route le Tahiti vers l’ISPF' do
      identifiant = described_class.parse('G33972001')
      expect(identifiant.source).to eq(:ispf)
      expect(identifiant.adapter_klass).to eq(APIEntreprise::PfEtablissementAdapter)
    end

    it 'route le SIRET vers API Entreprise' do
      identifiant = described_class.parse('41816609600051')
      expect(identifiant.source).to eq(:api_entreprise)
      expect(identifiant.adapter_klass).to eq(APIEntreprise::EtablissementAdapter)
    end

    it 'ne route rien pour un numéro invalide' do
      identifiant = described_class.parse('1234567890')
      expect(identifiant.source).to be_nil
      expect(identifiant.adapter_klass).to be_nil
    end
  end

  describe '#i18n_key' do
    it do
      expect(described_class.parse('G33972001').i18n_key).to eq(:tahiti)
      expect(described_class.parse('41816609600051').i18n_key).to eq(:siret)
      expect(described_class.parse('1234567890').i18n_key).to be_nil
    end
  end

  describe '#format_lisible' do
    it do
      expect(described_class.parse('G33972').format_lisible).to eq('G33972')
      expect(described_class.parse('G339720').format_lisible).to eq('G33972-0')
      expect(described_class.parse('G33972001').format_lisible).to eq('G33972-001')
      expect(described_class.parse('41816609600051').format_lisible).to eq('418 166 096 00051')
      expect(described_class.parse('1234567890').format_lisible).to eq('1234567890')
      expect(described_class.parse(nil).format_lisible).to eq('')
    end
  end

  describe '#annuaire_url' do
    it 'pointe vers la fiche ISPF pour un Tahiti complet' do
      expect(described_class.parse('G33972001').annuaire_url)
        .to eq('https://www.ispf.pf/rte/attestation/G33972/001')
    end

    it 'pointe vers la racine ISPF pour un Tahiti partiel' do
      expect(described_class.parse('G33972').annuaire_url).to eq('https://www.ispf.pf/rte')
    end

    it 'pointe vers l’annuaire des entreprises pour un SIRET' do
      expect(described_class.parse('41816609600051').annuaire_url)
        .to eq('https://annuaire-entreprises.data.gouv.fr/etablissement/41816609600051')
    end

    it 'retombe sur la racine ISPF pour un numéro invalide' do
      expect(described_class.parse('1234567890').annuaire_url).to eq('https://www.ispf.pf/rte')
    end
  end
end
