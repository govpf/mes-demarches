# Cohabitation numéro Tahiti / SIRET — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Faire fonctionner la saisie d'un identifiant d'entreprise — champ SIRET comme identification à l'entrée d'une démarche — indifféremment avec un numéro Tahiti (ISPF) ou un SIRET métropolitain (API Entreprise), avec une terminologie homogène.

**Architecture :** Un value object `IdentifiantEntreprise` devient la source unique de la règle « Tahiti ou SIRET ? », aujourd'hui réimplémentée dans sept fichiers avec quatorze comparaisons de longueur divergentes. Le validateur PF est renommé pour supprimer la collision de nom avec la gem `siret_validator` d'upstream. La terminologie est pilotée par `config/custom_locales/`, chargé après `config/locales/` et donc gagnant sans conflit de merge.

**Tech Stack :** Ruby 3.3.2, Rails 7.0.8.4, RSpec, WebMock, Capybara, Stimulus/TypeScript, I18n.

**Spec :** `docs/superpowers/specs/2026-08-19-identifiant-entreprise-tahiti-siret-design.md`

## Global Constraints

- **Branche de départ** : `feature/identifiant-entreprise-value-object`, basée sur `origin/devpf`. Les phases 2 à 4 partent chacune d'une branche distincte listée dans leur en-tête.
- **Aucune migration, aucun changement de schéma.** `Etablissement#siret` continue de stocker indifféremment 9 ou 14 caractères.
- **Typographie française obligatoire** dans tout texte destiné à l'interface : apostrophe courbe `’` et non `'`, guillemets `«  »`. Les specs qui assertent du texte d'interface doivent utiliser la même apostrophe.
- **Terme canonique** : `numéro Tahiti ou SIRET` — « Tahiti » en capitale initiale, « SIRET » en capitales. Exactement cette casse, partout.
- **Tags `# pf:`** obligatoires sur toute spécificité polynésienne introduite ou déplacée.
- **Hors périmètre, ne pas toucher** : en-têtes d'export, libellés de colonnes du tableau instructeur (`config/locales/models/procedure_presentation/fr.yml`), champ GraphQL `siret`.
- **Symboles d'erreur de validation** : conserver `:length` et `:checksum` (et non `:longueur`) pour que les clés de locale existantes continuent de résoudre. C'est une dérogation assumée au design, qui écrivait `:longueur`.
- **Lint** : `bundle exec rubocop -A` sur les fichiers touchés avant chaque commit.

---

# Phase 1 — Socle

**Branche :** `feature/identifiant-entreprise-value-object` (déjà créée, porte le design)

## Task 1 : le value object `IdentifiantEntreprise`

**Files:**
- Create: `app/models/identifiant_entreprise.rb`
- Test: `spec/models/identifiant_entreprise_spec.rb`

**Interfaces:**
- Consumes: rien.
- Produces: `IdentifiantEntreprise.parse(String|nil) → IdentifiantEntreprise`. Instance : `#valeur → String`, `#tahiti_partiel? → Boolean`, `#tahiti_complet? → Boolean`, `#tahiti? → Boolean`, `#siret? → Boolean`, `#valide? → Boolean`, `#erreur → Symbol|nil` (`:length` ou `:checksum`), `#adapter_klass → Class|nil`, `#source → Symbol|nil` (`:ispf` ou `:api_entreprise`), `#i18n_key → Symbol|nil` (`:tahiti` ou `:siret`), `#format_lisible → String`, `#annuaire_url → String`.

- [ ] **Step 1 : écrire le spec, table de vérité en premier**

Créer `spec/models/identifiant_entreprise_spec.rb` :

```ruby
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
        end

        it { expect(subject.valide?).to eq(valide) }
        it { expect(subject.erreur).to eq(erreur) }
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
    it { expect(described_class.parse('G33972')).to be_tahiti }
    it { expect(described_class.parse('G33972001')).to be_tahiti }
    it { expect(described_class.parse('41816609600051')).not_to be_tahiti }
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
    it { expect(described_class.parse('G33972001').i18n_key).to eq(:tahiti) }
    it { expect(described_class.parse('41816609600051').i18n_key).to eq(:siret) }
    it { expect(described_class.parse('1234567890').i18n_key).to be_nil }
  end

  describe '#format_lisible' do
    it { expect(described_class.parse('G33972').format_lisible).to eq('G33972') }
    it { expect(described_class.parse('G339720').format_lisible).to eq('G33972-0') }
    it { expect(described_class.parse('G33972001').format_lisible).to eq('G33972-001') }
    it { expect(described_class.parse('41816609600051').format_lisible).to eq('418 166 096 00051') }
    it { expect(described_class.parse('1234567890').format_lisible).to eq('1234567890') }
    it { expect(described_class.parse(nil).format_lisible).to eq('') }
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
```

- [ ] **Step 2 : lancer le spec pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/models/identifiant_entreprise_spec.rb`
Expected: FAIL — `NameError: uninitialized constant IdentifiantEntreprise`

- [ ] **Step 3 : écrire l'implémentation**

Créer `app/models/identifiant_entreprise.rb` :

```ruby
# frozen_string_literal: true

# pf: source unique de vérité pour la nature d'un identifiant d'entreprise.
#
# Deux référentiels cohabitent :
# - le numéro Tahiti de l'ISPF (référentiel i-taiete), 6 à 9 caractères
# - le SIRET métropolitain (API Entreprise), 14 chiffres
#
# Avant ce value object, la règle était réimplémentée dans sept fichiers avec
# quatorze comparaisons de longueur divergentes. Tout site qui doit savoir
# « Tahiti ou SIRET ? » passe désormais par ici.
class IdentifiantEntreprise
  # Les trois expressions sont mutuellement exclusives par construction :
  # elles n'acceptent pas les mêmes longueurs.
  TAHITI_PARTIEL = /\A[0-9A-Z]\d{5,7}\z/ # 6 à 8 car. : G33972, G339720, G3397200
  TAHITI_COMPLET = /\A[0-9A-Z]\d{8}\z/   # 9 car.     : G33972001
  SIRET          = /\A\d{14}\z/          # 14 chiffres

  # Seule exception à la règle de Luhn parmi les SIRET français.
  LA_POSTE_SIREN = '356000000'

  ANNUAIRE_ISPF = 'https://www.ispf.pf/rte'
  ANNUAIRE_FR   = 'https://annuaire-entreprises.data.gouv.fr/etablissement'

  attr_reader :valeur

  def self.parse(saisie)
    new(saisie.to_s.gsub(/[[:space:]-]/, '').upcase)
  end

  def initialize(valeur)
    @valeur = valeur
    freeze
  end

  # --- nature (mutuellement exclusifs) ---

  def tahiti_partiel? = valeur.match?(TAHITI_PARTIEL)

  def tahiti_complet? = valeur.match?(TAHITI_COMPLET)

  def siret? = valeur.match?(SIRET) && luhn_valide?

  # --- dérivés ---

  def tahiti? = tahiti_partiel? || tahiti_complet?

  def valide? = tahiti? || siret?

  # :checksum quand le format est bon mais la clé de Luhn fausse,
  # :length dans tous les autres cas d'invalidité.
  def erreur
    return nil if valide?
    return :checksum if valeur.match?(SIRET)
    :length
  end

  def source
    return :ispf if tahiti?
    return :api_entreprise if siret?
    nil
  end

  def adapter_klass
    case source
    when :ispf then APIEntreprise::PfEtablissementAdapter
    when :api_entreprise then APIEntreprise::EtablissementAdapter
    end
  end

  def i18n_key
    case source
    when :ispf then :tahiti
    when :api_entreprise then :siret
    end
  end

  def format_lisible
    if siret?
      "#{valeur[0..2]} #{valeur[3..5]} #{valeur[6..8]} #{valeur[9..]}"
    elsif tahiti? && valeur.length > 6
      "#{valeur[0..5]}-#{valeur[6..]}"
    else
      valeur
    end
  end

  def annuaire_url
    if tahiti_complet?
      "#{ANNUAIRE_ISPF}/attestation/#{valeur[0..5]}/#{valeur[6..]}"
    elsif siret?
      "#{ANNUAIRE_FR}/#{valeur}"
    else
      ANNUAIRE_ISPF
    end
  end

  private

  def luhn_valide?
    return true if valeur[0..8] == LA_POSTE_SIREN

    somme = valeur.reverse.each_char.map(&:to_i).each_with_index.sum do |chiffre, index|
      double = index.odd? ? chiffre * 2 : chiffre
      double < 10 ? double : double - 9
    end
    (somme % 10).zero?
  end
end
```

- [ ] **Step 4 : lancer le spec pour vérifier qu'il passe**

Run: `bundle exec rspec spec/models/identifiant_entreprise_spec.rb`
Expected: PASS, tous les exemples verts.

- [ ] **Step 5 : lint et commit**

```bash
bundle exec rubocop -A app/models/identifiant_entreprise.rb spec/models/identifiant_entreprise_spec.rb
git add app/models/identifiant_entreprise.rb spec/models/identifiant_entreprise_spec.rb
git commit -m "feat(siret): value object IdentifiantEntreprise, source unique de la règle Tahiti/SIRET"
```

---

## Task 2 : renommer le validateur et supprimer la collision avec la gem

Le fichier `app/validators/siret_validator.rb` porte le **même nom de classe** que la gem `siret_validator` retirée du Gemfile du fork mais toujours présente chez upstream. Le jour où un conflit Gemfile est résolu en faveur d'upstream, la gem revient, la constante est définie au boot par `Bundler.require`, et le fichier applicatif est ignoré : le validateur PF se désactive silencieusement et tous les numéros Tahiti se font rejeter. Renommer supprime le problème définitivement.

**Files:**
- Create: `app/validators/identifiant_entreprise_validator.rb`
- Delete: `app/validators/siret_validator.rb`
- Modify: `app/models/service.rb:26`, `app/models/siret.rb:10`, `app/models/champs/siret_champ.rb` (dans `validate_etablissement`)
- Test: `spec/models/siret_spec.rb`

**Interfaces:**
- Consumes: `IdentifiantEntreprise.parse`, `#valide?`, `#erreur` (Task 1).
- Produces: `IdentifiantEntrepriseValidator`, utilisable via `validates :attribut, identifiant_entreprise: true`.

- [ ] **Step 1 : ajouter les contextes Tahiti manquants au spec du modèle `Siret`**

`spec/models/siret_spec.rb` teste aujourd'hui sept cas, tous SIRET français : la moitié PF du validateur n'a jamais été couverte. Ajouter avant le `end` final :

```ruby
  # pf: le numéro Tahiti est le format dominant en Polynésie — il n'était
  # couvert par aucun exemple, d'où la divergence historique sur les 7-8 car.
  context 'with a 6-char Tahiti number' do
    let(:siret) { 'G33972' }

    it { is_expected.to be_valid }
  end

  context 'with a 7-char partial Tahiti number' do
    let(:siret) { 'G339720' }

    it { is_expected.to be_valid }
  end

  context 'with an 8-char partial Tahiti number' do
    let(:siret) { 'G3397200' }

    it { is_expected.to be_valid }
  end

  context 'with a 9-char Tahiti number' do
    let(:siret) { 'G33972001' }

    it { is_expected.to be_valid }
  end

  context 'with a 9-char numeric-only Tahiti number' do
    let(:siret) { '002253001' }

    it { is_expected.to be_valid }
  end

  context 'with a hyphen-formatted Tahiti number' do
    let(:siret) { 'G33972-001' }

    it { is_expected.to be_valid }
  end

  context 'with an 11-char number, neither Tahiti nor SIRET' do
    let(:siret) { '12345678901' }

    it { is_expected.to be_invalid }
  end
```

- [ ] **Step 2 : lancer le spec pour vérifier que les nouveaux cas échouent**

Run: `bundle exec rspec spec/models/siret_spec.rb`
Expected: les trois contextes 7-char, 8-char et hyphen-formatted **échouent** (`expected valid, got invalid`) — c'est le bug de divergence 7-8 caractères. Les autres passent déjà.

- [ ] **Step 3 : créer le nouveau validateur**

Créer `app/validators/identifiant_entreprise_validator.rb` :

```ruby
# frozen_string_literal: true

# pf: valide un identifiant d'entreprise, Tahiti (ISPF) ou SIRET (API Entreprise).
#
# Remplace l'ancien app/validators/siret_validator.rb, qui portait le même nom
# de classe que la gem siret_validator d'upstream : si un merge réintroduit la
# gem au Gemfile, elle définit la constante au boot et le fichier applicatif est
# ignoré, désactivant silencieusement la validation des numéros Tahiti. Le nom
# distinct supprime définitivement cette collision.
#
# Utilisé par : Service, Siret, Champs::SiretChamp.
class IdentifiantEntrepriseValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    identifiant = IdentifiantEntreprise.parse(value)
    return if identifiant.valide?

    record.errors.add(attribute, identifiant.erreur)
  end
end
```

- [ ] **Step 4 : basculer les trois appelants**

Dans `app/models/service.rb` ligne 26, remplacer :

```ruby
  validates :siret, siret: true
```

par :

```ruby
  # pf: validateur maison, accepte numéro Tahiti et SIRET (cf. IdentifiantEntreprise)
  validates :siret, identifiant_entreprise: true
```

Dans `app/models/siret.rb` ligne 10, remplacer :

```ruby
  validates :siret, siret: true
```

par :

```ruby
  # pf: validateur maison, accepte numéro Tahiti et SIRET (cf. IdentifiantEntreprise)
  validates :siret, identifiant_entreprise: true
```

Dans `app/models/champs/siret_champ.rb`, méthode privée `validate_etablissement`, remplacer :

```ruby
    # pf: custom SiretValidator accepts SIRET (14) and Tahiti (6/9)
    validator = SiretValidator.new(attributes: { external_id: true })
    validator.validate_each(self, :external_id, external_id)
```

par :

```ruby
    # pf: validateur maison, accepte numéro Tahiti (6-9) et SIRET (14)
    validator = IdentifiantEntrepriseValidator.new(attributes: { external_id: true })
    validator.validate_each(self, :external_id, external_id)
```

- [ ] **Step 5 : supprimer l'ancien validateur et vérifier qu'il ne reste aucune référence**

```bash
git rm app/validators/siret_validator.rb
grep -rn "SiretValidator" app/ spec/ lib/
grep -rnE "validates.*\bsiret: true" app/ spec/ lib/
```

Expected: aucune sortie pour les deux commandes. Le second `grep` est restreint aux
lignes `validates` : `siret: true` seul apparaît aussi dans des hash d'options sans
rapport avec la validation, qu'il ne faut pas toucher.

- [ ] **Step 6 : lancer les specs concernés**

Run:
```bash
bundle exec rspec spec/models/siret_spec.rb spec/models/champs/siret_champ_spec.rb spec/models/identifiant_entreprise_spec.rb
```
Expected: PASS. Les trois contextes 7-char, 8-char et hyphen-formatted passent maintenant — le bug de divergence est corrigé.

- [ ] **Step 7 : lancer les specs des modèles qui portent la validation**

Run: `bundle exec rspec spec/models/service_spec.rb`
Expected: PASS. Si un exemple assertait un message d'erreur, vérifier qu'il résout toujours (les symboles `:length` et `:checksum` sont inchangés, donc les clés de locale aussi).

- [ ] **Step 8 : lint et commit**

```bash
bundle exec rubocop -A app/validators/identifiant_entreprise_validator.rb app/models/service.rb app/models/siret.rb app/models/champs/siret_champ.rb spec/models/siret_spec.rb
git add -A
git commit -m "refactor(siret): renomme SiretValidator en IdentifiantEntrepriseValidator

Supprime la collision de nom avec la gem siret_validator d'upstream, dont le
retour au Gemfile désactiverait silencieusement la validation des numéros
Tahiti. Corrige au passage la divergence 7-8 caractères, acceptés par
Champs::SiretChamp mais rejetés par le validateur."
```

---

## Task 3 : aligner `Champs::SiretChamp` sur le value object

`ready_for_external_call?` accepte `6..9` et `fetch_external_data` dispatche sur `between?(6, 8)` : deux règles pour la même question, dans le même fichier.

**Files:**
- Modify: `app/models/champs/siret_champ.rb`
- Test: `spec/models/champs/siret_champ_spec.rb`

**Interfaces:**
- Consumes: `IdentifiantEntreprise` (Task 1).
- Produces: `Champs::SiretChamp#identifiant → IdentifiantEntreprise`, méthode publique réutilisée en Phase 3.

- [ ] **Step 1 : écrire les specs d'aiguillage**

Ajouter dans `spec/models/champs/siret_champ_spec.rb`, au niveau des autres `describe` :

Le fichier construit ses champs par `create(:procedure, types_de_champ_public: [{ type: :siret }])`
puis `dossier.champs.first` — il n'existe pas de factory `champ_siret`. Les `let`
`procedure`, `dossier`, `champ`, `external_id` et `etablissement` sont déjà définis en
tête de fichier (lignes 4-8) : les nouveaux `describe` réutilisent `external_id` en le
surchargeant, sans redéfinir `champ`.

```ruby
  # pf: l'aiguillage Tahiti/SIRET passe désormais par IdentifiantEntreprise
  describe '#ready_for_external_call?' do
    subject { champ.ready_for_external_call? }

    context 'with a 6-char Tahiti number' do
      let(:external_id) { 'G33972' }

      it { is_expected.to be true }
    end

    context 'with a 7-char partial Tahiti number' do
      let(:external_id) { 'G339720' }

      it { is_expected.to be true }
    end

    context 'with a 9-char Tahiti number' do
      let(:external_id) { 'G33972001' }

      it { is_expected.to be true }
    end

    context 'with a valid SIRET' do
      let(:external_id) { '41816609600051' }

      it { is_expected.to be true }
    end

    context 'with a Luhn-invalid SIRET' do
      let(:external_id) { '41816609600052' }

      it { is_expected.to be false }
    end

    # pf: 10 à 13 caractères partaient auparavant en appel API via `> 9`
    context 'with an 11-char number, neither Tahiti nor SIRET' do
      let(:external_id) { '12345678901' }

      it { is_expected.to be false }
    end

    context 'when blank' do
      let(:external_id) { nil }

      it { is_expected.to be false }
    end
  end

  describe '#identifiant' do
    let(:external_id) { 'g33972-001' }

    it 'expose le value object dérivé de external_id' do
      # `normalizes :external_id` retire déjà espaces et tirets à l'écriture ;
      # IdentifiantEntreprise renormalise pour être robuste aux lectures directes.
      expect(champ.identifiant.valeur).to eq('G33972001')
      expect(champ.identifiant).to be_tahiti_complet
    end
  end
```

- [ ] **Step 2 : lancer pour vérifier l'échec**

Run: `bundle exec rspec spec/models/champs/siret_champ_spec.rb -e "#identifiant"`
Expected: FAIL — `NoMethodError: undefined method 'identifiant'`

- [ ] **Step 3 : implémenter**

Dans `app/models/champs/siret_champ.rb`, ajouter la méthode publique après `uses_external_data?` :

```ruby
  # pf: nature de l'identifiant saisi — Tahiti (ISPF) ou SIRET (API Entreprise)
  def identifiant
    IdentifiantEntreprise.parse(external_id)
  end
```

Remplacer `ready_for_external_call?` :

```ruby
  def ready_for_external_call?
    # pf: accepte numéro Tahiti (6-9 car., partiel ou complet) et SIRET (14 chiffres)
    identifiant.valide?
  end
```

Remplacer la première ligne de `fetch_external_data` :

```ruby
  def fetch_external_data
    siret = external_id.to_s

    # pf: numéro Tahiti partiel (6-8 car.) : lister les candidats plutôt qu'une résolution unique
    return fetch_tahiti_candidates(siret) if identifiant.tahiti_partiel?
```

- [ ] **Step 4 : lancer les specs**

Run: `bundle exec rspec spec/models/champs/siret_champ_spec.rb`
Expected: PASS

- [ ] **Step 5 : lint et commit**

```bash
bundle exec rubocop -A app/models/champs/siret_champ.rb spec/models/champs/siret_champ_spec.rb
git add app/models/champs/siret_champ.rb spec/models/champs/siret_champ_spec.rb
git commit -m "refactor(siret): Champs::SiretChamp délègue l'aiguillage à IdentifiantEntreprise"
```

- [ ] **Step 6 : ouvrir la PR de la phase 1**

```bash
git push -u origin feature/identifiant-entreprise-value-object
gh pr create --base devpf --title "Socle : value object IdentifiantEntreprise (Tahiti / SIRET)" --body "$(cat <<'EOF'
Première étape du chantier de cohabitation numéro Tahiti / SIRET.

Design : `docs/superpowers/specs/2026-08-19-identifiant-entreprise-tahiti-siret-design.md`
Plan : `docs/superpowers/plans/2026-08-19-identifiant-entreprise-tahiti-siret.md`

## Contenu

- `IdentifiantEntreprise`, value object qui centralise la règle « Tahiti ou SIRET ? », jusqu'ici réimplémentée dans sept fichiers avec quatorze comparaisons de longueur divergentes
- `SiretValidator` renommé en `IdentifiantEntrepriseValidator` : supprime la collision de nom avec la gem `siret_validator` d'upstream, dont le retour au Gemfile désactiverait silencieusement la validation des numéros Tahiti
- `Champs::SiretChamp` délègue son aiguillage au value object

## Corrections fonctionnelles

- un numéro de 10 à 13 caractères est refusé immédiatement avec une erreur de format, au lieu de partir en appel API et de revenir en erreur réseau
- les numéros Tahiti de 7 à 8 caractères sont acceptés partout de la même façon : ils déclenchaient la recherche de candidats mais étaient rejetés à la soumission

## Tests

- `spec/models/identifiant_entreprise_spec.rb` : table de vérité exhaustive
- `spec/models/siret_spec.rb` : sept contextes Tahiti ajoutés — le format dominant en Polynésie n'était couvert par aucun exemple

Aucune migration, aucun changement de comportement API.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

# Phase 2 — Garde des jobs d'enrichissement

**Branche :** `fix/api-entreprise-jobs-guard`, basée sur la phase 1.

**⚠️ Cette phase est le prérequis de mise en production.** `perform_later_fetch_jobs` ne lance rien tant qu'aucun jeton n'est configuré. Comme `ApiEntrepriseTokenConcern#api_entreprise_token` retombe sur `ENV['API_ENTREPRISE_KEY']`, poser la variable lève ce garde pour toutes les démarches d'un coup : les dix jobs français partiraient interroger `entreprise.api.gouv.fr` avec des numéros Tahiti comme `G33972001`. **Ne pas poser `API_ENTREPRISE_KEY` en production avant que cette phase soit déployée.**

```bash
git checkout -b fix/api-entreprise-jobs-guard
```

## Task 4 : garder les jobs par la nature du numéro

**Files:**
- Modify: `app/services/api_entreprise_service.rb` (`perform_later_fetch_jobs`, lignes 120-145)
- Test: `spec/services/api_entreprise_service_spec.rb`

**Interfaces:**
- Consumes: `IdentifiantEntreprise` (Task 1).
- Produces: `APIEntrepriseService::FRENCH_ONLY_JOBS → Array<Class>`, constante réutilisée par les specs.

Répartition des jobs :
- **`APIEntreprise::EtablissementJob`** appelle `update_etablissement_from_degraded_mode`, qui dispatche entre les deux sources. Il est donc valable pour les deux référentiels et reste inconditionnel.
- **Les dix autres** (`EntrepriseJob`, `ExtraitKbisJob`, `TvaJob`, `AssociationJob`, `ExercicesJob`, `EffectifsJob`, `EffectifsAnnuelsJob`, `AttestationSocialeJob`, `BilansBdfJob`, `AttestationFiscaleJob`) interrogent exclusivement `entreprise.api.gouv.fr`.

- [ ] **Step 1 : écrire les specs du garde**

Ajouter dans `spec/services/api_entreprise_service_spec.rb`, au niveau des autres `describe` :

```ruby
  # pf: une fois API_ENTREPRISE_KEY posé en production, le garde « jeton présent ? »
  # tombe pour toutes les démarches — y compris celles dont les établissements
  # viennent de l'ISPF. Le garde doit porter sur la nature du numéro.
  describe '#perform_later_fetch_jobs — garde par nature du numéro' do
    let(:valid_token) { "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" }
    let(:procedure) { create(:procedure, api_entreprise_token: valid_token) }
    let(:dossier) { create(:dossier, procedure: procedure) }
    let(:etablissement) { create(:etablissement, dossier: dossier, siret: siret) }

    subject { APIEntrepriseService.perform_later_fetch_jobs(etablissement, procedure.id, nil) }

    before do
      allow_any_instance_of(APIEntrepriseToken).to receive(:roles).and_return([])
      allow_any_instance_of(APIEntrepriseToken).to receive(:expired?).and_return(false)
    end

    def jobs_enfiles
      ActiveJob::Base.queue_adapter.enqueued_jobs
        .map { |job| job[:job] }
        .select { |klass| klass.name.start_with?('APIEntreprise::') }
    end

    context 'with a Tahiti etablissement' do
      let(:siret) { 'G33972001' }

      it 'n’enfile aucun job français' do
        subject
        expect(jobs_enfiles).to be_empty
      end
    end

    context 'with a French SIRET etablissement' do
      let(:siret) { '41816609600051' }

      it 'enfile tous les jobs français' do
        subject
        expect(jobs_enfiles).to match_array(APIEntrepriseService::FRENCH_ONLY_JOBS)
      end
    end

    context 'with a Tahiti etablissement in degraded mode' do
      let(:siret) { 'G33972001' }
      let(:etablissement) { create(:etablissement, dossier: dossier, siret: siret, adresse: nil) }

      it 'n’enfile que EtablissementJob, qui sait router les deux sources' do
        subject
        expect(jobs_enfiles).to eq([APIEntreprise::EtablissementJob])
      end
    end

    context 'without any token' do
      let(:siret) { '41816609600051' }
      let(:procedure) { create(:procedure, api_entreprise_token: nil) }

      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('API_ENTREPRISE_KEY').and_return(nil)
      end

      it 'n’enfile rien, même pour un SIRET' do
        subject
        expect(jobs_enfiles).to be_empty
      end
    end
  end
```

- [ ] **Step 2 : lancer pour vérifier l'échec**

Run: `bundle exec rspec spec/services/api_entreprise_service_spec.rb -e "garde par nature du numéro"`
Expected: FAIL — `NameError: uninitialized constant APIEntrepriseService::FRENCH_ONLY_JOBS`, et le contexte Tahiti échoue parce que les jobs sont enfilés.

- [ ] **Step 3 : implémenter le garde**

Dans `app/services/api_entreprise_service.rb`, ajouter la constante juste après `class APIEntrepriseService` (avant `class << self`) :

```ruby
  # pf: ces jobs interrogent exclusivement entreprise.api.gouv.fr — ils n'ont
  # aucun sens sur un établissement issu du référentiel ISPF.
  # APIEntreprise::EtablissementJob en est volontairement absent : il appelle
  # update_etablissement_from_degraded_mode, qui dispatche entre les deux sources.
  FRENCH_ONLY_JOBS = [
    APIEntreprise::EntrepriseJob, APIEntreprise::ExtraitKbisJob, APIEntreprise::TvaJob,
    APIEntreprise::AssociationJob, APIEntreprise::ExercicesJob,
    APIEntreprise::EffectifsJob, APIEntreprise::EffectifsAnnuelsJob,
    APIEntreprise::AttestationSocialeJob, APIEntreprise::BilansBdfJob,
    APIEntreprise::AttestationFiscaleJob,
  ].freeze
```

Remplacer intégralement `perform_later_fetch_jobs` :

```ruby
    def perform_later_fetch_jobs(etablissement, procedure_id, user_id, wait: nil)
      # pf: sans jeton (procédure ou ENV), ces jobs lèvent tous TokenError et
      # finissent morts dans Sidekiq. Un jeton spécifique sur la procédure reste honoré.
      return if Procedure.find_by(id: procedure_id)&.api_entreprise_token&.jwt_token.blank?

      identifiant = IdentifiantEntreprise.parse(etablissement.siret)

      jobs = []
      # EtablissementJob sait router les deux référentiels : il vaut pour un
      # numéro Tahiti comme pour un SIRET.
      jobs << APIEntreprise::EtablissementJob if etablissement.as_degraded_mode?
      # pf: les autres jobs sont strictement français — poser API_ENTREPRISE_KEY
      # ne doit pas les déclencher sur les établissements issus de l'ISPF.
      jobs.concat(FRENCH_ONLY_JOBS) if identifiant.siret?

      jobs.each do |job|
        if job == APIEntreprise::AttestationFiscaleJob
          job.set(wait:).perform_later(etablissement.id, procedure_id, user_id)
        else
          job.set(wait:).perform_later(etablissement.id, procedure_id)
        end
      end
    end
```

- [ ] **Step 4 : lancer les specs**

Run: `bundle exec rspec spec/services/api_entreprise_service_spec.rb`
Expected: PASS. Le `shared_examples 'schedule fetch of all etablissement params'` existant doit toujours passer — il utilise le SIRET `30613890001294`, donc `identifiant.siret?` est vrai.

- [ ] **Step 5 : lint et commit**

```bash
bundle exec rubocop -A app/services/api_entreprise_service.rb spec/services/api_entreprise_service_spec.rb
git add app/services/api_entreprise_service.rb spec/services/api_entreprise_service_spec.rb
git commit -m "fix(siret): garde les jobs API Entreprise par la nature du numéro

Poser API_ENTREPRISE_KEY lève le garde « jeton présent ? » pour toutes les
démarches d'un coup : les dix jobs français partiraient interroger
entreprise.api.gouv.fr avec des numéros Tahiti. Le garde porte désormais sur
IdentifiantEntreprise#siret?."
```

---

## Task 5 : router les sondes de santé vers la bonne API

`service_unavailable_error?(target: :insee)` appelle `api_insee_up?`, qui pointe en dur sur l'API ISPF. Un SIRET français qui échoue est diagnostiqué avec la santé d'i-taiete ; inversement, si i-taiete tombe pendant qu'API Entreprise va bien, un dossier SIRET bascule à tort en mode dégradé. `fr_api_insee_up?` existe déjà dans le même fichier (ligne 147) et n'est appelée nulle part.

**Files:**
- Modify: `app/services/api_entreprise_service.rb` (`service_unavailable_error?`, ligne 155)
- Modify: `app/models/champs/siret_champ.rb:64`
- Modify: `app/controllers/users/dossiers_controller.rb:258` et `:620`
- Test: `spec/services/api_entreprise_service_spec.rb`

**Interfaces:**
- Consumes: `IdentifiantEntreprise` (Task 1), `Champs::SiretChamp#identifiant` (Task 3).
- Produces: `APIEntrepriseService.service_unavailable_error?(error, target:, identifiant: nil)` — nouveau paramètre nommé optionnel, rétrocompatible.

- [ ] **Step 1 : écrire les specs de routage**

Ajouter dans `spec/services/api_entreprise_service_spec.rb` :

```ruby
  # pf: deux fournisseurs, donc deux sondes de santé. Diagnostiquer un échec
  # SIRET avec la santé d'i-taiete (ou l'inverse) fait basculer des dossiers en
  # mode dégradé à tort.
  describe '#service_unavailable_error? — routage des sondes' do
    let(:error) { double('error', network_error?: true, is_a?: false) }

    before do
      stub_request(:get, "https://entreprise.api.gouv.fr/ping/insee/sirene")
        .to_return(body: Rails.root.join('spec/fixtures/files/api_entreprise/ping.json').read, status: 200)
      stub_request(:get, API_ISPF_URL).to_return(status: 200)
    end

    context 'with a French SIRET' do
      let(:identifiant) { IdentifiantEntreprise.parse('41816609600051') }

      it 'interroge la sonde API Entreprise et non celle de l’ISPF' do
        expect(described_class).to receive(:fr_api_insee_up?).and_return(false)
        expect(described_class).not_to receive(:api_insee_up?)
        expect(described_class.service_unavailable_error?(error, target: :insee, identifiant:)).to be true
      end
    end

    context 'with a Tahiti number' do
      let(:identifiant) { IdentifiantEntreprise.parse('G33972001') }

      it 'interroge la sonde ISPF et non celle d’API Entreprise' do
        expect(described_class).to receive(:api_insee_up?).and_return(false)
        expect(described_class).not_to receive(:fr_api_insee_up?)
        expect(described_class.service_unavailable_error?(error, target: :insee, identifiant:)).to be true
      end
    end

    context 'without identifiant' do
      it 'retombe sur la sonde ISPF, comportement historique' do
        expect(described_class).to receive(:api_insee_up?).and_return(false)
        expect(described_class.service_unavailable_error?(error, target: :insee)).to be true
      end
    end
  end
```

- [ ] **Step 2 : lancer pour vérifier l'échec**

Run: `bundle exec rspec spec/services/api_entreprise_service_spec.rb -e "routage des sondes"`
Expected: FAIL — le contexte SIRET échoue, `api_insee_up?` est appelée au lieu de `fr_api_insee_up?`.

- [ ] **Step 3 : router dans le service**

Dans `app/services/api_entreprise_service.rb`, remplacer `service_unavailable_error?` :

```ruby
    def service_unavailable_error?(error, target:, identifiant: nil)
      return false if !error.try(:network_error?)

      if target == :insee
        # pf: deux fournisseurs — sonder celui qui a réellement été interrogé.
        # Sans identifiant, on retombe sur l'ISPF (référentiel dominant en PF).
        return true if identifiant&.siret? ? !fr_api_insee_up? : !api_insee_up?
      end
      return true if target == :djepva && !APIEntrepriseService.api_djepva_up?

      error.is_a?(APIEntreprise::API::Error::ServiceUnavailable)
    end
```

- [ ] **Step 4 : transmettre l'identifiant depuis les trois appelants**

Dans `app/models/champs/siret_champ.rb`, méthode `fetch_external_data`, remplacer :

```ruby
    if APIEntrepriseService.service_unavailable_error?(error, target: :insee)
```

par :

```ruby
    if APIEntrepriseService.service_unavailable_error?(error, target: :insee, identifiant:)
```

Dans `app/controllers/users/dossiers_controller.rb`, méthode `update_siret` (ligne 258 environ), remplacer :

```ruby
                          if APIEntrepriseService.service_unavailable_error?(error, target: :insee)
```

par :

```ruby
                          if APIEntrepriseService.service_unavailable_error?(error, target: :insee, identifiant:)
```

Dans la même méthode, ajouter juste après `current_user.siret = sanitized_siret = siret_model.siret` :

```ruby
      # pf: nature du numéro saisi — pilote l'aiguillage API et le diagnostic de panne
      identifiant = IdentifiantEntreprise.parse(sanitized_siret)
```

Dans `create_etablissement_and_redirect` (ligne 620 environ), remplacer :

```ruby
    def create_etablissement_and_redirect(siret)
      etablissement = begin
        APIEntrepriseService.create_etablissement(@dossier, siret, current_user.id)
                      rescue APIEntreprise::API::Error, APIEntrepriseToken::TokenError => error
                        if APIEntrepriseService.service_unavailable_error?(error, target: :insee)
```

par :

```ruby
    def create_etablissement_and_redirect(siret)
      # pf: nature du numéro — pilote le diagnostic de panne (ISPF ou API Entreprise)
      identifiant = IdentifiantEntreprise.parse(siret)
      etablissement = begin
        APIEntrepriseService.create_etablissement(@dossier, siret, current_user.id)
                      rescue APIEntreprise::API::Error, APIEntrepriseToken::TokenError => error
                        if APIEntrepriseService.service_unavailable_error?(error, target: :insee, identifiant:)
```

- [ ] **Step 5 : lancer les specs**

Run:
```bash
bundle exec rspec spec/services/api_entreprise_service_spec.rb spec/models/champs/siret_champ_spec.rb spec/controllers/users/dossiers_controller_spec.rb
```
Expected: PASS

- [ ] **Step 6 : lint et commit**

```bash
bundle exec rubocop -A app/services/api_entreprise_service.rb app/models/champs/siret_champ.rb app/controllers/users/dossiers_controller.rb
git add -A
git commit -m "fix(siret): route les sondes de santé vers l'API réellement interrogée

fr_api_insee_up? existait sans appelant. Un échec SIRET était diagnostiqué avec
la santé d'i-taiete, et une panne ISPF faisait basculer les dossiers SIRET en
mode dégradé à tort."
```

- [ ] **Step 7 : ouvrir la PR de la phase 2**

```bash
git push -u origin fix/api-entreprise-jobs-guard
gh pr create --base devpf --title "Garde des jobs API Entreprise par nature du numéro" --body "$(cat <<'EOF'
Deuxième étape du chantier Tahiti / SIRET. **Prérequis de mise en production.**

## Pourquoi maintenant

`ApiEntrepriseTokenConcern#api_entreprise_token` retombe sur `ENV['API_ENTREPRISE_KEY']`. Poser cette variable lève le garde de `perform_later_fetch_jobs` pour toutes les démarches d'un coup : les dix jobs français partiraient interroger `entreprise.api.gouv.fr` avec des numéros Tahiti comme `G33972001`, produisant une vague de 404 dans Sidekiq.

**Cette PR doit être déployée avant de poser `API_ENTREPRISE_KEY`.**

## Contenu

- le garde porte désormais sur `IdentifiantEntreprise#siret?` et non sur la présence d'un jeton (qui reste en second rideau)
- `APIEntreprise::EtablissementJob` reste inconditionnel : il appelle `update_etablissement_from_degraded_mode`, qui sait router les deux référentiels
- `fr_api_insee_up?`, définie sans appelant depuis son introduction, est branchée : un échec SIRET est diagnostiqué avec la santé d'API Entreprise, un échec Tahiti avec celle de l'ISPF

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 8 : après déploiement — poser la variable d'environnement**

Une fois la phase 2 déployée en production, poser `API_ENTREPRISE_KEY` avec le jeton API Entreprise obtenu. **À cet instant, le SIRET français fonctionne déjà de bout en bout** : `update_siret` route déjà `> 9` vers `EtablissementAdapter` et le champ SIRET accepte déjà 14 caractères. Vérifier manuellement :

1. créer un dossier sur une démarche « personne morale »
2. saisir `41816609600051` (ou tout SIRET réel)
3. l'établissement est résolu, la raison sociale s'affiche
4. dans Sidekiq, vérifier qu'aucun job `APIEntreprise::*` n'échoue sur des numéros Tahiti

Rollback : retirer la variable ramène exactement au comportement antérieur.

---

# Phase 3 — Routage unifié

**Branche :** `feature/routage-identifiant-entreprise`, basée sur la phase 2.

```bash
git checkout -b feature/routage-identifiant-entreprise
```

## Task 6 : unifier le routage dans `APIEntrepriseService`

Trois méthodes comptent des caractères avec des règles différentes : `list_etablissements` (`< 9`), `create_etablissement` (`== 9` / `> 9` / sinon nil), `update_etablissement_from_degraded_mode` (`>= 6 && <= 9` / `> 9`).

**Files:**
- Modify: `app/services/api_entreprise_service.rb` (`list_etablissements` lignes 5-17, `create_etablissement` lignes 19-70, `update_etablissement_from_degraded_mode` lignes 88-115)
- Test: `spec/services/api_entreprise_service_spec.rb`

**Interfaces:**
- Consumes: `IdentifiantEntreprise` (Task 1).
- Produces: signatures publiques inchangées — `list_etablissements(siret_prefix, procedure_id = nil)`, `create_etablissement(dossier_or_champ, siret, user_id = nil)`, `update_etablissement_from_degraded_mode(etablissement, procedure_id)`.

- [ ] **Step 1 : écrire les specs de routage**

Ajouter dans `spec/services/api_entreprise_service_spec.rb` :

```ruby
  # pf: le routage passait par des comparaisons de longueur divergentes selon la
  # méthode. Un numéro de 10 à 13 caractères partait en appel API via `> 9`.
  describe '#create_etablissement — routage par nature du numéro' do
    let(:procedure) { create(:procedure, api_entreprise_token: nil) }
    let(:dossier) { create(:dossier, procedure: procedure) }

    subject { APIEntrepriseService.create_etablissement(dossier, siret, nil) }

    context 'with an 11-char number, neither Tahiti nor SIRET' do
      let(:siret) { '12345678901' }

      it 'renvoie nil sans aucun appel réseau' do
        expect(APIEntreprise::EtablissementAdapter).not_to receive(:new)
        expect(APIEntreprise::PfEtablissementAdapter).not_to receive(:new)
        expect(subject).to be_nil
      end
    end

    context 'with a partial Tahiti number' do
      let(:siret) { 'G33972' }

      it 'renvoie nil — la résolution passe par list_etablissements' do
        expect(subject).to be_nil
      end
    end
  end

  describe '#list_etablissements — routage par nature du numéro' do
    subject { APIEntrepriseService.list_etablissements(saisie, nil) }

    context 'with a complete Tahiti number' do
      let(:saisie) { 'G33972001' }

      it 'renvoie nil — un numéro complet se résout directement' do
        expect(subject).to be_nil
      end
    end

    context 'with an 11-char number' do
      let(:saisie) { '12345678901' }

      it 'renvoie nil sans appel réseau' do
        expect(APIEntreprise::PfEtablissementAdapter).not_to receive(:new)
        expect(subject).to be_nil
      end
    end
  end
```

- [ ] **Step 2 : lancer pour vérifier l'échec**

Run: `bundle exec rspec spec/services/api_entreprise_service_spec.rb -e "routage par nature du numéro"`
Expected: FAIL — le contexte 11 caractères de `create_etablissement` instancie `EtablissementAdapter` (via `> 9`).

- [ ] **Step 3 : réécrire `list_etablissements`**

```ruby
    # pf: un numéro Tahiti partiel (6 à 8 car.) peut correspondre à plusieurs
    # établissements. On les liste pour que l'usager choisisse.
    def list_etablissements(siret_prefix, procedure_id = nil)
      identifiant = IdentifiantEntreprise.parse(siret_prefix)
      return nil unless identifiant.tahiti_partiel?

      begin
        APIEntreprise::PfEtablissementAdapter.new(identifiant.valeur, procedure_id).to_all_etablissements
      rescue APIEntreprise::API::Error::ResourceNotFound
        nil
      end
    end
```

- [ ] **Step 4 : réécrire `create_etablissement`**

```ruby
    def create_etablissement(dossier_or_champ, siret, user_id = nil)
      procedure_id = dossier_or_champ.procedure.id
      identifiant = IdentifiantEntreprise.parse(siret)

      etablissement_params = if identifiant.tahiti_complet?
        APIEntreprise::PfEtablissementAdapter.new(identifiant.valeur, procedure_id).to_params
      elsif identifiant.siret?
        APIEntreprise::EtablissementAdapter.new(identifiant.valeur, procedure_id).to_params
      else
        # pf: numéro Tahiti partiel → passer par list_etablissements ;
        # numéro invalide → rien à résoudre.
        return nil
      end

      return nil if etablissement_params.blank?

      if identifiant.siret?
        entreprise_params = APIEntreprise::EntrepriseAdapter.new(identifiant.valeur, procedure_id).to_params
        etablissement_params.merge!(entreprise_params) if entreprise_params.any?
      end

      etablissement = dossier_or_champ.build_etablissement(etablissement_params)
      etablissement.save!

      if dossier_or_champ.is_a?(Champ)
        dossier_or_champ.update!(value_json: APIGeoService.parse_etablissement_address(etablissement))
      end
      # perform_later_fetch_jobs s'auto-garde depuis la phase 2 (nature du numéro
      # + présence du jeton) — pas de condition à dupliquer ici.
      perform_later_fetch_jobs(etablissement, procedure_id, user_id)
      # pf: la cascade explicite des formules est déclenchée par
      # Etablissement#update_champ_value_json! (couvre les cas Champ et Dossier).
      etablissement.update_champ_value_json!
      etablissement
    end
```

- [ ] **Step 5 : réécrire `update_etablissement_from_degraded_mode`**

```ruby
    def update_etablissement_from_degraded_mode(etablissement, procedure_id)
      identifiant = IdentifiantEntreprise.parse(etablissement.siret)

      etablissement_params = if identifiant.tahiti?
        # pf: en mode dégradé, un numéro partiel ne peut pas être auto-complété
        # (plusieurs candidats possibles). On ne valide que si l'adapter a rendu
        # un numéro complet à 9 caractères.
        params = APIEntreprise::PfEtablissementAdapter.new(identifiant.valeur, procedure_id).to_params
        return nil unless params.present? && IdentifiantEntreprise.parse(params[:siret]).tahiti_complet?

        params
      elsif identifiant.siret?
        APIEntreprise::EtablissementAdapter.new(identifiant.valeur, procedure_id).to_params
      else
        return nil
      end
      return nil if etablissement_params.empty?

      etablissement.update!(etablissement_params)
      etablissement.update_champ_value_json!

      etablissement
    end
```

- [ ] **Step 6 : lancer les specs du service et des consommateurs**

Run:
```bash
bundle exec rspec spec/services/api_entreprise_service_spec.rb spec/models/champs/siret_champ_spec.rb spec/jobs/cron/backfill_siret_degraded_mode_job_spec.rb spec/lib/api_entreprise/pf_etablissement_adapter_spec.rb
```
Expected: PASS

- [ ] **Step 7 : lint et commit**

```bash
bundle exec rubocop -A app/services/api_entreprise_service.rb spec/services/api_entreprise_service_spec.rb
git add app/services/api_entreprise_service.rb spec/services/api_entreprise_service_spec.rb
git commit -m "refactor(siret): APIEntrepriseService route par IdentifiantEntreprise

Supprime les règles divergentes entre create_etablissement (== 9 / > 9),
list_etablissements (< 9) et update_etablissement_from_degraded_mode (6..9)."
```

---

## Task 7 : unifier le routage dans le contrôleur

`update_siret` teste `< 9` puis `== 14` à deux endroits pour choisir le message d'erreur.

**Files:**
- Modify: `app/controllers/users/dossiers_controller.rb` (`update_siret`, lignes 214-280)
- Test: `spec/controllers/users/dossiers_controller_spec.rb`

**Interfaces:**
- Consumes: `IdentifiantEntreprise` (Task 1), `identifiant` local posé en Task 5 Step 4.
- Produces: rien de nouveau.

- [ ] **Step 1 : écrire les specs du contrôleur**

Ajouter dans `spec/controllers/users/dossiers_controller_spec.rb`, dans le `describe '#update_siret'` existant (ou en créer un) :

```ruby
  # pf: un numéro ni Tahiti ni SIRET doit être refusé sur le format, sans appel réseau
  describe '#update_siret — refus de format' do
    let(:user) { create(:user) }
    let(:procedure) { create(:procedure, :published, :for_individual_and_personne_morale) }
    let(:dossier) { create(:dossier, user: user, procedure: procedure) }

    before { sign_in(user) }

    subject do
      post :update_siret, params: { id: dossier.id, user: { siret: '12345678901' } }
    end

    it 'rend le formulaire sans appeler les services de résolution' do
      expect(APIEntrepriseService).not_to receive(:create_etablissement)
      expect(APIEntrepriseService).not_to receive(:list_etablissements)
      subject
      expect(response).to render_template(:siret)
    end
  end
```

Adapter le nom de la factory de procédure et le helper d'authentification aux
conventions réellement utilisées dans le fichier — les lire en tête de
`spec/controllers/users/dossiers_controller_spec.rb` avant d'écrire.

- [ ] **Step 2 : lancer pour vérifier l'échec**

Run: `bundle exec rspec spec/controllers/users/dossiers_controller_spec.rb -e "11-char number"`
Expected: FAIL — `create_etablissement` est appelée via la branche `else`.

- [ ] **Step 3 : réécrire l'aiguillage de `update_siret`**

Remplacer la condition `if sanitized_siret.length < 9` par :

```ruby
      # pf: numéro Tahiti partiel — plusieurs établissements possibles
      if identifiant.tahiti_partiel?
```

Dans la branche `else`, remplacer les deux tests `if sanitized_siret.length == 14` par `if identifiant.siret?` :

```ruby
                            Sentry.capture_exception(error, extra: { dossier_id: @dossier.id, siret: sanitized_siret })
                            if identifiant.siret?
                              return render_siret_error(t('errors.messages.siret.network_error'))
                            else
                              return render_siret_error(t('errors.messages.siret_network_error'))
                            end
```

et :

```ruby
        if etablissement.nil?
          if identifiant.siret?
            return render_siret_error(t('errors.messages.siret.not_found'))
          else
            return render_siret_error(t('errors.messages.siret_unknown'))
          end
        end
```

Note : le cas « numéro invalide » est déjà intercepté en amont par `siret_model.valid?` (le validateur de Task 2 rejette les 10-13 caractères), donc la branche `else` ne reçoit plus que des numéros Tahiti complets ou des SIRET.

- [ ] **Step 4 : lancer les specs du contrôleur**

Run: `bundle exec rspec spec/controllers/users/dossiers_controller_spec.rb`
Expected: PASS

- [ ] **Step 5 : lint et commit**

```bash
bundle exec rubocop -A app/controllers/users/dossiers_controller.rb spec/controllers/users/dossiers_controller_spec.rb
git add app/controllers/users/dossiers_controller.rb spec/controllers/users/dossiers_controller_spec.rb
git commit -m "refactor(siret): update_siret route par IdentifiantEntreprise"
```

---

## Task 8 : mise en forme et lien annuaire

`pretty_siret` compte les caractères une septième fois. `annuaire_link` construit `ispf.pf/rte/attestation/#{siret.first(6)}/#{siret.last(3)}` **sans discriminer** : pour un SIRET à 14 chiffres il produit une URL ISPF avec les 6 premiers et 3 derniers chiffres d'un numéro français. Lien mort, silencieux.

**Files:**
- Modify: `app/helpers/etablissement_helper.rb:37-50`, `app/helpers/dossier_helper.rb:229-233`
- Test: `spec/helpers/etablissement_helper_spec.rb`, `spec/helpers/dossier_helper_spec.rb`

**Interfaces:**
- Consumes: `IdentifiantEntreprise#format_lisible`, `#annuaire_url` (Task 1).
- Produces: `pretty_siret(String) → String|nil`, `annuaire_link(String|nil) → String` — signatures inchangées.

- [ ] **Step 1 : écrire les specs des helpers**

Ajouter dans `spec/helpers/etablissement_helper_spec.rb` :

```ruby
  describe '#pretty_siret' do
    it { expect(helper.pretty_siret(nil)).to be_nil }
    it { expect(helper.pretty_siret('G33972001')).to eq('G33972-001') }
    it { expect(helper.pretty_siret('g33972-001')).to eq('G33972-001') }
    it { expect(helper.pretty_siret('41816609600051')).to eq('418 166 096 00051') }
    # pf: un numéro Tahiti partiel reste lisible
    it { expect(helper.pretty_siret('G339720')).to eq('G33972-0') }
  end
```

Ajouter dans `spec/helpers/dossier_helper_spec.rb` :

```ruby
  describe '#annuaire_link' do
    it 'renvoie la racine ISPF sans numéro' do
      expect(helper.annuaire_link).to eq('https://www.ispf.pf/rte')
    end

    it 'renvoie la fiche ISPF pour un numéro Tahiti' do
      expect(helper.annuaire_link('G33972001')).to eq('https://www.ispf.pf/rte/attestation/G33972/001')
    end

    # pf: sans discrimination, un SIRET produisait une URL ISPF absurde
    it 'renvoie l’annuaire des entreprises pour un SIRET' do
      expect(helper.annuaire_link('41816609600051'))
        .to eq('https://annuaire-entreprises.data.gouv.fr/etablissement/41816609600051')
    end
  end
```

- [ ] **Step 2 : lancer pour vérifier l'échec**

Run: `bundle exec rspec spec/helpers/etablissement_helper_spec.rb spec/helpers/dossier_helper_spec.rb`
Expected: FAIL sur le SIRET dans `annuaire_link` (URL ISPF absurde) et sur le Tahiti partiel dans `pretty_siret`.

- [ ] **Step 3 : implémenter**

Dans `app/helpers/etablissement_helper.rb`, remplacer `pretty_siret` :

```ruby
  def pretty_siret(siret)
    return if siret.blank?
    # pf: la mise en forme dépend du référentiel (Tahiti ou SIRET)
    IdentifiantEntreprise.parse(siret).format_lisible
  end
```

Dans `app/helpers/dossier_helper.rb`, remplacer `annuaire_link` :

```ruby
  def annuaire_link(siren_or_siret = nil)
    # pf: l'annuaire dépend du référentiel — ISPF pour un numéro Tahiti,
    # annuaire-entreprises.data.gouv.fr pour un SIRET
    IdentifiantEntreprise.parse(siren_or_siret).annuaire_url
  end
```

- [ ] **Step 4 : lancer les specs**

Run:
```bash
bundle exec rspec spec/helpers/etablissement_helper_spec.rb spec/helpers/dossier_helper_spec.rb spec/views/users/dossiers/siret.html.haml_spec.rb spec/views/users/dossiers/etablissement.html.haml_spec.rb
```
Expected: PASS

- [ ] **Step 5 : lint et commit**

```bash
bundle exec rubocop -A app/helpers/etablissement_helper.rb app/helpers/dossier_helper.rb
git add -A
git commit -m "fix(siret): pretty_siret et annuaire_link discriminent le référentiel

annuaire_link construisait une URL ISPF avec les 6 premiers et 3 derniers
chiffres d'un SIRET français — lien mort silencieux."
```

---

## Task 9 : aligner la mise en forme à la frappe

`format_controller.ts` réimplémente les règles en TypeScript. Lors de la saisie d'un SIRET, au neuvième caractère la valeur `123456789` correspond au motif Tahiti et un tiret est inséré — la frappe se répare au caractère suivant, mais l'affichage saute.

**Files:**
- Create: `app/javascript/shared/identifiant-entreprise.ts`
- Modify: `app/javascript/controllers/format_controller.ts` (`formatSIRET`, lignes 67-75)
- Test: `spec/system/users/dossier_creation_spec.rb` (couverture indirecte via Task 10)

**Interfaces:**
- Consumes: rien (miroir TypeScript des constantes de `IdentifiantEntreprise`).
- Produces: `formatIdentifiantEntreprise(value: string): string`, exportée depuis `app/javascript/shared/identifiant-entreprise.ts`.

- [ ] **Step 1 : créer le module partagé**

Créer `app/javascript/shared/identifiant-entreprise.ts` :

```typescript
// pf: miroir TypeScript de app/models/identifiant_entreprise.rb.
// Toute modification des règles doit être répercutée des deux côtés — la mise
// en forme à la frappe doit suivre exactement la validation serveur.
const TAHITI_PARTIEL = /^[0-9A-Z]\d{5,7}$/; // 6 à 8 caractères
const TAHITI_COMPLET = /^[0-9A-Z]\d{8}$/; // 9 caractères
const SIRET = /^\d{14}$/; // 14 chiffres

/** Retire espaces et tirets, met en capitales. */
function normalise(value: string): string {
  return value.replace(/[\s-]/g, '').toUpperCase();
}

/**
 * Met en forme un identifiant d'entreprise selon son référentiel :
 * - SIRET complet     : "418 166 096 00051"
 * - Tahiti 7 à 9 car. : "G33972-001"
 * - tout le reste     : rendu tel quel, la saisie est en cours
 */
export function formatIdentifiantEntreprise(value: string): string {
  const brut = normalise(value);

  if (SIRET.test(brut)) {
    return `${brut.slice(0, 3)} ${brut.slice(3, 6)} ${brut.slice(6, 9)} ${brut.slice(9)}`;
  }
  // Un numéro de 9 chiffres est ambigu pendant la frappe : ce peut être un
  // numéro Tahiti complet ou les 9 premiers chiffres d'un SIRET. On n'insère le
  // tiret que si la valeur ne peut pas devenir un SIRET, c'est-à-dire si elle
  // commence par une lettre.
  const peutDevenirSiret = /^\d+$/.test(brut) && brut.length < 14;
  if (!peutDevenirSiret && (TAHITI_COMPLET.test(brut) || TAHITI_PARTIEL.test(brut)) && brut.length > 6) {
    return `${brut.slice(0, 6)}-${brut.slice(6)}`;
  }
  return brut;
}
```

- [ ] **Step 2 : brancher le contrôleur Stimulus**

Dans `app/javascript/controllers/format_controller.ts`, ajouter en tête du fichier :

```typescript
import { formatIdentifiantEntreprise } from '../shared/identifiant-entreprise';
```

Remplacer intégralement la méthode privée `formatSIRET` :

```typescript
  private formatSIRET(value: string) {
    // pf: règles centralisées dans shared/identifiant-entreprise.ts, miroir du
    // value object IdentifiantEntreprise côté serveur
    return formatIdentifiantEntreprise(value);
  }
```

- [ ] **Step 3 : vérifier la compilation**

Run: `yarn tsc --noEmit`
Expected: aucune erreur. Si `tsc` n'est pas configuré en standalone, utiliser `bin/vite build` et vérifier l'absence d'erreur.

- [ ] **Step 4 : lint et commit**

```bash
yarn lint --fix app/javascript/shared/identifiant-entreprise.ts app/javascript/controllers/format_controller.ts
git add app/javascript/shared/identifiant-entreprise.ts app/javascript/controllers/format_controller.ts
git commit -m "refactor(siret): centralise la mise en forme à la frappe

Un numéro purement numérique de 9 chiffres ne reçoit plus de tiret : pendant la
saisie d'un SIRET, il pouvait s'insérer puis disparaître au caractère suivant."
```

---

## Task 10 : scénarios système de bout en bout

L'historique du projet montre que les bugs se logent dans le déclenchement, pas dans le calcul. Le scénario 3 est celui qu'aucun test unitaire n'attrapera : il croise le chantier SIRET avec la cascade des formules.

**Files:**
- Create: `spec/system/users/identifiant_entreprise_spec.rb`
- Modify: `spec/system/users/dossier_creation_spec.rb:144` (le libellé change en phase 4, pas ici)

**Interfaces:**
- Consumes: tout ce qui précède.
- Produces: rien.

- [ ] **Step 1 : écrire les trois scénarios**

Créer `spec/system/users/identifiant_entreprise_spec.rb` :

```ruby
# frozen_string_literal: true

describe 'Identification d’une entreprise, numéro Tahiti ou SIRET', js: true do
  let(:user) { create(:user) }
  # pf: l'identification par numéro d'entreprise s'obtient par ABSENCE du trait
  # :for_individual — il n'existe pas de trait :for_individual_and_personne_morale.
  # Convention reprise de spec/system/users/dossier_creation_spec.rb:115.
  let(:procedure) { create(:procedure, :published, :with_service, :with_type_de_champ) }
  let(:siret_fr) { '41816609600051' }
  let(:siren_fr) { siret_fr[0...9] }
  let(:tahiti_prefix) { 'G33972' }

  before { login_as user, scope: :user }

  # --- Scénario 1 : SIRET français ---
  context 'avec un SIRET métropolitain' do
    before do
      stub_etablissement_fr
      allow_any_instance_of(APIEntrepriseToken).to receive(:roles).and_return([])
      allow_any_instance_of(APIEntrepriseToken).to receive(:expired?).and_return(false)
    end

    scenario 'résout l’établissement et poursuit le dossier' do
      visit commencer_path(path: procedure.path)
      click_on 'Commencer la démarche'

      fill_in_identifiant_entreprise(siret_fr)
      click_on 'Continuer'

      # pf: raison sociale portée par la fixture etablissements.json
      expect(page).to have_content('Coiff Land, CoiffureLand')
      # pf: l'annuaire doit désigner le référentiel du numéro saisi
      expect(page).to have_link(href: %r{annuaire-entreprises\.data\.gouv\.fr})

      click_on 'Continuer avec ces informations'
      expect(page).to have_current_path(brouillon_dossier_path(procedure.dossiers.last))
    end
  end

  # --- Scénario 2 : numéro Tahiti partiel, non-régression du parcours dominant ---
  context 'avec un numéro Tahiti partiel correspondant à plusieurs établissements' do
    before do
      stub_request(:get, %r{#{API_ISPF_URL}/etablissements/Entreprise})
        .with(query: hash_including(numeroTahiti: tahiti_prefix))
        .to_return(body: File.read('spec/fixtures/files/api_entreprise/pf_etablissements_multiples.json'), status: 200)
    end

    scenario 'propose la liste et enregistre le choix de l’usager' do
      visit commencer_path(path: procedure.path)
      click_on 'Commencer la démarche'

      fill_in_identifiant_entreprise(tahiti_prefix)
      click_on 'Continuer'

      expect(page).to have_content('Plusieurs établissements')
      first('[data-etablissement-choice]').click
      click_on 'Continuer'

      expect(page).to have_current_path(etablissement_dossier_path(Dossier.last))
    end
  end

  # --- Scénario 3 : bascule d'un référentiel à l'autre dans un champ SIRET ---
  context 'en remplaçant un numéro Tahiti par un SIRET dans un champ' do
    let(:procedure) do
      create(:procedure, :published, types_de_champ_public: [
        { type: :siret, libelle: 'Établissement' },
        { type: :formule, libelle: 'Dénomination reprise', options: { expression: 'champ("Établissement").raison_sociale' } },
      ])
    end
    let(:dossier) { create(:dossier, procedure: procedure, user: user) }

    before do
      stub_request(:get, %r{#{API_ISPF_URL}/etablissements/Entreprise})
        .to_return(body: File.read('spec/fixtures/files/api_entreprise/pf_etablissement_unique.json'), status: 200)
      stub_etablissement_fr
      allow_any_instance_of(APIEntrepriseToken).to receive(:roles).and_return([])
      allow_any_instance_of(APIEntrepriseToken).to receive(:expired?).and_return(false)
    end

    scenario 'nettoie l’ancien établissement et recalcule la formule dépendante' do
      visit brouillon_dossier_path(dossier)

      fill_in 'Établissement', with: 'G33972001'
      expect(page).to have_field('Dénomination reprise', with: /.+/)
      denomination_tahiti = find_field('Dénomination reprise').value

      # bascule vers un SIRET métropolitain
      fill_in 'Établissement', with: siret_fr

      expect(page).to have_content('Coiff Land, CoiffureLand')
      # pf: la cascade des formules doit se redéclencher — c'est le point que
      # refresh_formulas_after garantit dans SiretChamp#update_external_data!
      expect(find_field('Dénomination reprise').value).not_to eq(denomination_tahiti)
      expect(find_field('Dénomination reprise').value).to include('Coiff')

      champ = dossier.reload.project_champs_public.find { |c| c.libelle == 'Établissement' }
      expect(champ.etablissement.siret).to eq(siret_fr)
    end
  end

  def fill_in_identifiant_entreprise(valeur)
    # pf: le libellé du champ est piloté par les locales (cf. phase 4) —
    # on cible le champ par son nom pour rester stable au changement de libellé.
    find('input[name="user[siret]"]').set(valeur)
  end

  def stub_etablissement_fr
    stub_request(:get, %r{https://entreprise\.api\.gouv\.fr/v3/insee/sirene/etablissements/#{siret_fr}})
      .to_return(body: File.read('spec/fixtures/files/api_entreprise/etablissements.json'), status: 200)
    stub_request(:get, %r{https://entreprise\.api\.gouv\.fr/v3/insee/sirene/unites_legales/#{siren_fr}})
      .to_return(body: File.read('spec/fixtures/files/api_entreprise/entreprises.json'), status: 200)
  end
end
```

- [ ] **Step 2 : créer les fixtures ISPF manquantes**

Vérifier si les fixtures existent :

```bash
ls spec/fixtures/files/api_entreprise/pf_etablissements_multiples.json spec/fixtures/files/api_entreprise/pf_etablissement_unique.json 2>/dev/null
ls spec/fixtures/cassettes/pf_api_entreprise.yml
```

Si les deux premières sont absentes, les extraire de la cassette existante `spec/fixtures/cassettes/pf_api_entreprise.yml` (qui contient une réponse i-taiete réelle) :

```bash
ruby -ryaml -rjson -e '
  cassette = YAML.load_file("spec/fixtures/cassettes/pf_api_entreprise.yml")
  body = cassette["http_interactions"].first.dig("response", "body", "string")
  parsed = JSON.parse(body)
  File.write("spec/fixtures/files/api_entreprise/pf_etablissement_unique.json", JSON.pretty_generate(parsed.first(1)))
  File.write("spec/fixtures/files/api_entreprise/pf_etablissements_multiples.json", JSON.pretty_generate(parsed))
  puts "unique: #{parsed.first(1).size} établissement, multiples: #{parsed.size}"
'
```

Si la cassette ne contient qu'un seul établissement, dupliquer l'entrée dans `pf_etablissements_multiples.json` en incrémentant `numEtablissement` (1 puis 2) pour obtenir un cas ambigu.

- [ ] **Step 3 : lancer les scénarios**

Run: `bundle exec rspec spec/system/users/identifiant_entreprise_spec.rb --format documentation`
Expected: PASS sur les trois scénarios.

En cas d'échec sur les sélecteurs (`[data-etablissement-choice]`, libellés) : lire `app/components/editable_champ/etablissements_list_component/etablissements_list_component.html.haml` et `app/views/users/dossiers/etablissements.html.haml` pour ajuster aux sélecteurs réels. Ne pas contourner un échec en relâchant l'assertion sur la cascade des formules du scénario 3 — c'est le cœur du test.

- [ ] **Step 4 : lancer la suite système SIRET complète pour vérifier l'absence de régression**

Run: `bundle exec rspec spec/system/users/dossier_creation_spec.rb spec/system/users/brouillon_spec.rb spec/system/users/polynesian_fields_spec.rb --format documentation`
Expected: PASS

- [ ] **Step 5 : commit**

```bash
git add spec/system/users/identifiant_entreprise_spec.rb spec/fixtures/files/api_entreprise/
git commit -m "test(siret): scénarios système Tahiti / SIRET, dont la bascule avec cascade des formules"
```

- [ ] **Step 6 : ouvrir la PR de la phase 3**

```bash
git push -u origin feature/routage-identifiant-entreprise
gh pr create --base devpf --title "Routage unifié Tahiti / SIRET" --body "$(cat <<'EOF'
Troisième étape du chantier Tahiti / SIRET. Supprime les quatorze comparaisons de longueur dispersées.

## Contenu

- `APIEntrepriseService` (`create_etablissement`, `list_etablissements`, `update_etablissement_from_degraded_mode`) et `Users::DossiersController#update_siret` routent par `IdentifiantEntreprise`
- `pretty_siret` et `annuaire_link` discriminent le référentiel — `annuaire_link` construisait une URL ISPF avec les 6 premiers et 3 derniers chiffres d'un SIRET français, lien mort silencieux
- la mise en forme à la frappe est centralisée dans `app/javascript/shared/identifiant-entreprise.ts`, miroir du value object

## Tests

Trois scénarios système, dont la bascule Tahiti → SIRET dans un champ, qui vérifie que la cascade des formules se redéclenche. C'est l'interaction entre deux sous-systèmes qu'aucun test unitaire ne couvre.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

# Phase 4 — Terminologie

**Branche :** `feature/terminologie-identifiant-entreprise`, basée sur la phase 3.

```bash
git checkout -b feature/terminologie-identifiant-entreprise
```

## Task 11 : surcharge de terminologie dans `custom_locales`

`config/custom_locales/` existe déjà, est vide, et `config/application.rb:41` le charge **après** `config/locales/**`. I18n fait un deep-merge où le dernier chargé gagne. Toutes les surcharges PF y vont, et on cesse de patcher les fichiers de locales upstream : un merge qui réécrit `config/locales/fr.yml` passe alors sans conflit *et* notre terme gagne quand même.

**Files:**
- Create: `config/custom_locales/entreprise.fr.yml`, `config/custom_locales/entreprise.en.yml`
- Test: `spec/i18n/terminologie_entreprise_spec.rb`

**Interfaces:**
- Consumes: rien.
- Produces: les clés surchargées listées ci-dessous.

- [ ] **Step 1 : relever l'état des clés concernées**

```bash
grep -rn "TAHITI\|Tahiti\|SIRET" config/locales/models/etablissement/fr.yml config/locales/models/siret/fr.yml config/locales/models/service/fr.yml config/locales/models/champs/siret_champ/fr.yml
sed -n '680,684p' config/locales/fr.yml
```

Attendu — trois formulations concurrentes pour la même donnée :

| Clé | Valeur actuelle |
| --- | --- |
| `activerecord.attributes.siret` (etablissement) | `SIRET` |
| `activerecord.attributes.siret_siege_social` | `SIRET du siège social` |
| `activerecord.attributes.user.siret` | `Numéro TAHITI` |
| `activerecord.attributes.service.siret` | `Numéro TAHITI` |
| `activemodel.models.siret` | `Numéro TAHITI` |
| `activerecord.attributes.champs/siret_champ.hints.value` | `Saisissez 9 chiffres (Tahiti) ou 14 chiffres (SIRET)…` |

- [ ] **Step 2 : écrire le spec de garde**

Créer `spec/i18n/terminologie_entreprise_spec.rb` :

```ruby
# frozen_string_literal: true

# pf: ces specs ne testent pas du code, ils testent une discipline.
# Leur rôle est de faire échouer la CI au prochain merge upstream plutôt que de
# laisser une régression de libellé partir en production.
# Clés qui désignent l'identifiant d'entreprise sans savoir de quel référentiel
# il relève : elles doivent mentionner les deux. Défini hors du bloc describe
# pour ne pas déclencher Lint/ConstantDefinitionInBlock.
CLES_TERMINOLOGIE_ENTREPRISE = [
  'activerecord.attributes.siret',
  'activerecord.attributes.siret_siege_social',
  'activerecord.attributes.user.siret',
  'activerecord.attributes.service.siret',
  'activemodel.models.siret',
].freeze

describe 'Terminologie de l’identifiant d’entreprise' do
  describe 'chaque clé sensible mentionne les deux référentiels' do
    CLES_TERMINOLOGIE_ENTREPRISE.each do |cle|
      it "#{cle} mentionne Tahiti et SIRET" do
        valeur = I18n.t(cle, locale: :fr)

        expect(valeur).to be_a(String), "#{cle} n’existe pas ou n’est pas une chaîne"
        expect(valeur).to match(/Tahiti/i),
          "#{cle} = #{valeur.inspect} — upstream a probablement réintroduit « SIRET » seul"
        expect(valeur).to match(/SIRET/i),
          "#{cle} = #{valeur.inspect} — le SIRET métropolitain doit être mentionné"
      end
    end
  end

  # Une surcharge dans custom_locales cesse silencieusement de s'appliquer si
  # upstream renomme ou supprime la clé d'origine. Ce test la transforme en
  # échec explicite.
  describe 'aucune surcharge orpheline dans custom_locales' do
    # Le backend I18n de l'application fusionne config/locales ET custom_locales :
    # y chercher une clé la trouverait toujours, puisque la surcharge l'y a mise.
    # Il faut donc un backend neuf chargé du seul amont pour que le garde détecte
    # réellement une clé qu'upstream a renommée ou supprimée.
    let(:traductions_amont) do
      backend = I18n::Backend::Simple.new
      Rails.root.glob('config/locales/**/*.yml').each { |f| backend.load_translations(f) }
      backend.send(:translations)
    end

    def chemins_de_cles(hash, prefixe = [])
      hash.flat_map do |cle, valeur|
        chemin = prefixe + [cle.to_s]
        valeur.is_a?(Hash) ? chemins_de_cles(valeur, chemin) : [chemin]
      end
    end

    Dir[Rails.root.join('config/custom_locales/**/*.yml')].each do |fichier|
      context File.basename(fichier) do
        it 'ne surcharge que des clés existant dans config/locales' do
          contenu = YAML.load_file(fichier)

          contenu.each do |locale, arbre|
            chemins_de_cles(arbre).each do |chemin|
              cle = chemin.join('.')
              valeur_amont = chemin.reduce(traductions_amont[locale.to_sym]) do |noeud, segment|
                noeud.is_a?(Hash) ? noeud[segment.to_sym] : nil
              end

              expect(valeur_amont).not_to be_nil,
                "#{cle} (#{locale}) est surchargée mais n’existe plus en amont — " \
                'upstream l’a probablement renommée ou supprimée, la surcharge ne s’applique plus'
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 3 : lancer pour vérifier l'échec**

Run: `bundle exec rspec spec/i18n/terminologie_entreprise_spec.rb`
Expected: FAIL sur `activerecord.attributes.siret` (= `SIRET`, aucune mention de Tahiti) et sur les clés `Numéro TAHITI` (aucune mention de SIRET).

- [ ] **Step 4 : écrire les surcharges**

Créer `config/custom_locales/entreprise.fr.yml` :

```yaml
# pf: surcharge de terminologie de l'identifiant d'entreprise.
#
# Ce répertoire est chargé APRÈS config/locales/** (cf. config/application.rb),
# et I18n fait un deep-merge où le dernier chargé gagne. Conséquence : les
# fichiers de locales upstream ne sont plus patchés, un merge qui les réécrit
# passe sans conflit, et notre terminologie gagne quand même.
#
# Terme canonique : « numéro Tahiti ou SIRET » — Tahiti en capitale initiale,
# SIRET en capitales. Ne pas dévier de cette casse.
#
# Toute clé ajoutée ici doit exister dans config/locales, sinon la surcharge ne
# s'applique pas : spec/i18n/terminologie_entreprise_spec.rb le vérifie.
---
fr:
  activerecord:
    attributes:
      # Bloc d'identité d'entreprise (Dossiers::IdentiteEntrepriseComponent,
      # via Etablissement.human_attribute_name)
      siret: "Numéro Tahiti ou SIRET"
      siret_siege_social: "Numéro Tahiti ou SIRET du siège social"
      user:
        siret: "Numéro Tahiti ou SIRET"
      service:
        siret: "Numéro Tahiti ou SIRET"
      champs/siret_champ:
        hints:
          # pf: pas d'exemple purement numérique ici — la mise en forme à la frappe
          # ne pose pas de tiret sur un numéro de 9 chiffres, indiscernable des 9
          # premiers chiffres d'un SIRET en cours de saisie (cf. Task 9).
          value: "Numéro Tahiti à 6 ou 9 caractères (ex. G33972-001) ou numéro SIRET à 14 chiffres (ex. 418 166 096 00051)."
    errors:
      models:
        champs/siret_champ:
          attributes:
            external_id:
              length: "doit être un numéro Tahiti (6 à 9 caractères) ou un numéro SIRET (14 chiffres)"
  activemodel:
    models:
      siret: "Numéro Tahiti ou SIRET"
    errors:
      models:
        siret:
          attributes:
            siret:
              length: "est invalide. Attendu : un numéro Tahiti (6 à 9 caractères, commençant par une lettre ou un chiffre) ou un numéro SIRET à 14 chiffres"
  errors:
    messages:
      invalid_siret_length: "Le numéro doit être un numéro Tahiti (6 à 9 caractères) ou un numéro SIRET (14 chiffres)."
      siret_not_found: "Nous n’avons pas trouvé d’établissement correspondant à ce numéro Tahiti ou SIRET."
```

Créer `config/custom_locales/entreprise.en.yml` :

```yaml
# pf: English counterpart of entreprise.fr.yml — see that file for the rationale.
---
en:
  activerecord:
    attributes:
      siret: "Tahiti number or SIRET"
      siret_siege_social: "Head office Tahiti number or SIRET"
      user:
        siret: "Tahiti number or SIRET"
      service:
        siret: "Tahiti number or SIRET"
  activemodel:
    models:
      siret: "Tahiti number or SIRET"
```

Note : le spec de garde n'inspecte que la locale `:fr` pour la terminologie, mais vérifie l'absence de surcharge orpheline dans **tous** les fichiers, y compris `entreprise.en.yml`. Si une clé anglaise n'existe pas en amont, le spec la signalera — la retirer du fichier plutôt que de l'inventer.

- [ ] **Step 5 : lancer le spec de garde**

Run: `bundle exec rspec spec/i18n/terminologie_entreprise_spec.rb`
Expected: PASS. Si le second test signale une surcharge orpheline, retirer la clé fautive du fichier YAML — c'est le comportement attendu du garde, pas un bug du spec.

- [ ] **Step 6 : lancer les specs qui assertent ces libellés**

Run:
```bash
bundle exec rspec spec/views/users/dossiers/siret.html.haml_spec.rb spec/views/shared/dossiers/_identite_entreprise.html.haml_spec.rb spec/models/siret_spec.rb spec/models/champs/siret_champ_spec.rb spec/controllers/administrateurs/services_controller_spec.rb
```
Expected: des échecs sur les messages d'erreur assertés en dur. Mettre à jour chaque attente avec le nouveau texte — en respectant l'apostrophe courbe `’`.

- [ ] **Step 7 : corriger la spec système qui cible le libellé**

`spec/system/users/dossier_creation_spec.rb:144` fait `fill_in 'Numéro TAHITI', with: siret`. Remplacer par :

```ruby
        fill_in 'Numéro Tahiti ou SIRET', with: siret
```

Run: `bundle exec rspec spec/system/users/dossier_creation_spec.rb`
Expected: PASS

- [ ] **Step 8 : lint et commit**

```bash
bundle exec rubocop -A spec/i18n/terminologie_entreprise_spec.rb
git add config/custom_locales/ spec/i18n/ spec/
git commit -m "feat(siret): terminologie « numéro Tahiti ou SIRET » via custom_locales

config/custom_locales est chargé après config/locales : les fichiers upstream ne
sont plus patchés, un merge qui les réécrit passe sans conflit et notre terme
gagne quand même. Deux specs de garde détectent la réintroduction de « SIRET »
seul et les surcharges devenues orphelines."
```

---

## Task 12 : converger sur le composant upstream

Deux chemins de rendu coexistent pour la même donnée : `Dossiers::IdentiteEntrepriseComponent` (upstream, résout ses libellés par `Etablissement.human_attribute_name`) et `app/views/shared/dossiers/_identite_entreprise.html.haml` (ancienne vue, libellés en dur). Un instructeur lit « SIRET » sur la page demande d'un dossier et « Numéro TAHITI » sur l'impression du même dossier.

Upstream est en train de supprimer l'ancienne vue. La convergence supprime le conflit de merge permanent et fait bénéficier tous les écrans de la surcharge de Task 11 d'un coup.

**Files:**
- Modify: `app/views/shared/champs/siret/_show.html.haml`, `app/views/instructeurs/dossiers/print.html.haml:13`
- Delete: `app/views/shared/dossiers/_identite_entreprise.html.haml`, `spec/views/shared/dossiers/_identite_entreprise.html.haml_spec.rb`
- Test: specs système et de vues existants

**Interfaces:**
- Consumes: `Dossiers::IdentiteEntrepriseComponent.new(champ:, etablissement:, avis:)`, `Dossiers::DegradedIdentiteEntrepriseComponent.new(etablissement:, profile:)`.
- Produces: rien.

- [ ] **Step 1 : recenser les appelants de l'ancienne vue**

```bash
grep -rn "shared/dossiers/identite_entreprise" app/ spec/
```

Attendu : `app/views/shared/champs/siret/_show.html.haml`, `app/views/instructeurs/dossiers/print.html.haml:13`, et le spec de vue.

- [ ] **Step 2 : comparer le rendu des deux chemins avant de basculer**

Lire les deux implémentations côte à côte pour repérer ce que l'ancienne vue affiche et que le composant n'affiche pas :

```bash
sed -n '1,120p' app/views/shared/dossiers/_identite_entreprise.html.haml
sed -n '1,140p' app/components/dossiers/identite_entreprise_component.rb
```

Noter dans le message de commit toute donnée présente d'un seul côté (bilans Banque de France, effectifs, exercices…). Si l'ancienne vue affiche une donnée absente du composant, **ne pas la perdre** : l'ajouter au composant dans un commit distinct plutôt que de renoncer à la convergence.

- [ ] **Step 3 : basculer `_show.html.haml`**

Remplacer dans `app/views/shared/champs/siret/_show.html.haml` :

```haml
  = render partial: "shared/dossiers/identite_entreprise", locals: { etablissement: champ.etablissement, profile: profile, champ: }
```

par :

```haml
  -# pf: convergence sur le composant upstream — l'ancienne vue portait ses
  -# libellés en dur, d'où un conflit à chaque merge et « SIRET » ici,
  -# « Numéro TAHITI » là pour la même donnée.
  - if champ.etablissement.as_degraded_mode?
    = render Dossiers::DegradedIdentiteEntrepriseComponent.new(etablissement: champ.etablissement, profile: profile)
  - else
    = render Dossiers::IdentiteEntrepriseComponent.new(champ: champ)
```

- [ ] **Step 4 : basculer `print.html.haml`**

Remplacer ligne 13 de `app/views/instructeurs/dossiers/print.html.haml` :

```haml
  = render partial: "shared/dossiers/identite_entreprise", locals: { etablissement: @dossier.etablissement, profile: 'instructeur' }
```

par :

```haml
  -# pf: convergence sur le composant upstream (cf. shared/champs/siret/_show)
  - if @dossier.etablissement.as_degraded_mode?
    = render Dossiers::DegradedIdentiteEntrepriseComponent.new(etablissement: @dossier.etablissement, profile: 'instructeur')
  - else
    = render Dossiers::IdentiteEntrepriseComponent.new(etablissement: @dossier.etablissement)
```

- [ ] **Step 5 : supprimer l'ancienne vue et son spec**

```bash
git rm app/views/shared/dossiers/_identite_entreprise.html.haml
git rm spec/views/shared/dossiers/_identite_entreprise.html.haml_spec.rb
grep -rn "shared/dossiers/identite_entreprise" app/ spec/
```

Expected du `grep` : uniquement `views.shared.dossiers.identite_entreprise` utilisé comme **scope de traduction** (dans `app/views/users/dossiers/etablissement.html.haml` et `app/components/dossiers/short_identite_entreprise_component.html.haml`), qui n'est pas un chemin de partial et doit rester. Aucun `render partial:`.

- [ ] **Step 6 : lancer les specs de vues et système**

Run:
```bash
bundle exec rspec spec/views/ spec/components/ --format progress
bundle exec rspec spec/system/instructeurs/instruction_spec.rb spec/system/users/dossier_creation_spec.rb --format documentation
```
Expected: PASS

- [ ] **Step 7 : vérifier visuellement les deux écrans**

Lancer l'application et comparer :
1. page demande d'un dossier instructeur (`Dossiers::IdentiteEntrepriseComponent`, inchangé)
2. impression du même dossier (`print`, basculé) — le libellé doit maintenant être « Numéro Tahiti ou SIRET », identique au premier écran
3. affichage d'un champ SIRET en lecture (`shared/champs/siret/_show`, basculé)

- [ ] **Step 8 : commit**

```bash
git add -A
git commit -m "refactor(siret): converge sur Dossiers::IdentiteEntrepriseComponent

L'ancienne vue _identite_entreprise.html.haml portait ses libellés en dur : un
instructeur lisait « SIRET » sur la page demande et « Numéro TAHITI » sur
l'impression du même dossier. Upstream la remplace par un composant qui résout
ses libellés via human_attribute_name — la surcharge custom_locales s'applique
donc partout d'un coup, et le conflit de merge permanent disparaît."
```

---

## Task 13 : libellés de saisie

Le formulaire d'identification ne sait pas encore quel référentiel l'usager va utiliser : il doit présenter les deux à égalité, avec les deux annuaires.

**Files:**
- Modify: `config/locales/fr.yml` (bloc `views.users.dossiers.identite`, lignes 477-488), `config/locales/en.yml` (bloc équivalent, lignes ~471-482)
- Modify: `app/views/users/dossiers/siret.html.haml`
- Modify: `app/views/shared/champs/siret/_etablissement.html.haml` (chaîne en dur ligne 25)
- Test: `spec/views/users/dossiers/siret.html.haml_spec.rb`

**Interfaces:**
- Consumes: `annuaire_link` (Task 8).
- Produces: nouvelles clés `views.users.dossiers.identite.siret_help_fr_html` et `views.users.dossiers.identite.etablissement_pending`.

Note : ces clés sont **nouvelles**, donc absentes de `config/locales` upstream. Elles vont dans `config/locales/fr.yml` et non dans `custom_locales` — le garde de Task 11 exige qu'une clé surchargée existe en amont, et une clé qu'on crée n'a pas d'amont. `custom_locales` est réservé aux **surcharges** de clés upstream.

- [ ] **Step 1 : réécrire le bloc de libellés de saisie**

Dans `config/locales/fr.yml`, remplacer le bloc `identite` (lignes 481-486) :

```yaml
          # pf: deux référentiels cohabitent — numéro Tahiti (ISPF) et SIRET (API Entreprise)
          complete_siret: Renseignez le numéro d’identification de votre entreprise, administration ou association pour commencer la démarche.
          siret_placeholder: numéro Tahiti ou SIRET
          siret_help_html: "Polynésie française : numéro Tahiti à 6 ou 9 caractères, à retrouver sur %{annuaire_link} ou auprès de votre service comptable."
          siret_help_fr_html: "Métropole et outre-mer : numéro SIRET à 14 chiffres, à retrouver sur %{annuaire_fr_link}."
          annuaire_link_title: Rechercher un numéro Tahiti sur l’annuaire des entreprises de Polynésie française
          annuaire_fr_link_title: Rechercher un numéro SIRET sur l’Annuaire des Entreprises
```

Dans `config/locales/en.yml`, le bloc équivalent :

```yaml
          # pf: two registries coexist — Tahiti number (ISPF) and SIRET (API Entreprise)
          complete_siret: Enter your company, administration or association identification number to start.
          siret_placeholder: Tahiti number or SIRET
          siret_help_html: "French Polynesia: 6 or 9-character Tahiti number, available on %{annuaire_link} or from your accounting department."
          siret_help_fr_html: "Mainland France and overseas: 14-digit SIRET number, available on %{annuaire_fr_link}."
          annuaire_link_title: Search for a Tahiti number on the French Polynesia business directory
          annuaire_fr_link_title: Search for a SIRET number on the Annuaire des Entreprises
```

- [ ] **Step 2 : réécrire la vue de saisie**

Dans `app/views/users/dossiers/siret.html.haml`, remplacer le `.fr-fieldset__element` d'aide :

```haml
        .fr-fieldset__element
          -# pf: deux référentiels présentés à égalité — l'usager ignore lequel
          -# le concerne avant de lire cette aide
          %p.fr-text--sm= t('views.users.dossiers.identite.siret_help_html',
                            annuaire_link: link_to('ispf.pf/rte', annuaire_link, title: new_tab_suffix(t('views.users.dossiers.identite.annuaire_link_title')), **external_link_attributes))
          %p.fr-text--sm= t('views.users.dossiers.identite.siret_help_fr_html',
                            annuaire_fr_link: link_to('annuaire-entreprises.data.gouv.fr', 'https://annuaire-entreprises.data.gouv.fr', title: new_tab_suffix(t('views.users.dossiers.identite.annuaire_fr_link_title')), **external_link_attributes))
```

- [ ] **Step 3 : externaliser la dernière chaîne en dur du champ SIRET**

Dans `app/views/shared/champs/siret/_etablissement.html.haml`, remplacer la ligne finale :

```haml
    %p.fr-info-text Ce numéro TAHITI existe, nous en récupérons les informations.
```

par :

```haml
    %p.fr-info-text= t('views.users.dossiers.identite.etablissement_pending')
```

Ajouter la clé dans `config/locales/fr.yml`, bloc `identite` :

```yaml
          etablissement_pending: Ce numéro existe, nous en récupérons les informations.
```

et dans `config/locales/en.yml` :

```yaml
          etablissement_pending: This number exists, we are retrieving its information.
```

- [ ] **Step 4 : lancer les specs de vues**

Run:
```bash
bundle exec rspec spec/views/users/dossiers/siret.html.haml_spec.rb spec/views/users/dossiers/etablissement.html.haml_spec.rb
```
Expected: PASS. Mettre à jour toute attente sur l'ancien texte, apostrophe courbe comprise.

- [ ] **Step 5 : lancer la suite système et le spec de garde i18n**

Run:
```bash
bundle exec rspec spec/i18n/terminologie_entreprise_spec.rb spec/system/users/identifiant_entreprise_spec.rb spec/system/users/dossier_creation_spec.rb --format documentation
```
Expected: PASS

- [ ] **Step 6 : lancer la suite complète**

Run: `bundle exec rspec --format progress`
Expected: PASS. Puis `bundle exec rails lint`.

- [ ] **Step 7 : commit et PR de la phase 4**

```bash
git add -A
git commit -m "feat(siret): libellés de saisie présentant les deux référentiels

Le formulaire d'identification ne sait pas quel référentiel l'usager va
utiliser : il présente le numéro Tahiti et le SIRET à égalité, avec leurs deux
annuaires. Externalise la dernière chaîne en dur du champ SIRET."

git push -u origin feature/terminologie-identifiant-entreprise
gh pr create --base devpf --title "Terminologie homogène « numéro Tahiti ou SIRET »" --body "$(cat <<'EOF'
Quatrième et dernière étape du chantier Tahiti / SIRET.

## Le problème

Trois formulations concurrentes désignaient la même donnée : `activerecord.attributes.siret` disait « SIRET » (jamais traduit depuis upstream), `activerecord.attributes.user.siret` disait « Numéro TAHITI », et sept vues portaient le libellé en dur dans le HAML. Concrètement, un instructeur lisait « SIRET » sur la page demande d'un dossier et « Numéro TAHITI » sur l'impression du même dossier.

## La solution

- **`config/custom_locales/`** — le répertoire existait, vide, chargé après `config/locales/**`. Toutes les surcharges de terminologie y vont : les fichiers upstream ne sont plus patchés, un merge qui les réécrit passe sans conflit, et notre terme gagne quand même.
- **Convergence sur `Dossiers::IdentiteEntrepriseComponent`** — l'ancienne vue PF est supprimée au profit du composant upstream, qui résout ses libellés via `human_attribute_name`. La surcharge s'applique donc partout d'un coup.
- **Deux specs de garde** — le premier détecte la réintroduction de « SIRET » seul par upstream, le second détecte les surcharges devenues orphelines quand upstream renomme une clé. Ces specs testent une discipline, pas du code : leur rôle est de faire échouer la CI au prochain merge plutôt que de laisser passer une régression de libellé.

## Hors périmètre

En-têtes d'export, libellés de colonnes du tableau instructeur et champ GraphQL `siret` sont inchangés — les modifier casserait les scripts des instructeurs. Vérifié : ces surfaces lisent `config/locales/models/procedure_presentation/fr.yml` et non `human_attribute_name`, la surcharge ne les touche donc pas.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

# Hors périmètre de ce plan

**PR 5 — contribution i18n upstream.** Deux vues portent du français en dur sans clés de locale, et upstream ne les a pas migrées : `app/views/users/dossiers/etablissement.html.haml` (« L'annuaire INSEE est indisponible… », « Utiliser un autre numéro SIRET ») et `app/views/administrateurs/services/_form.html.haml` (trois phrases). L'argument tient sans rien devoir à la Polynésie : un usager en locale anglaise y voit du français alors que le dépôt contient les traductions.

Cette PR se fait dans le dépôt `demarche-numerique/demarche.numerique.gouv.fr` et non ici. Elle est **hors du chemin critique** — plusieurs semaines jusqu'au merge, puis plusieurs mois avant qu'elle revienne dans une release intégrée. À ouvrir **avant** d'externaliser localement, pour que les noms de clés soient fixés par la revue upstream et qu'on ne se crée pas un conflit avec sa propre contribution.

**`Cron::BackfillSiretDegradedModeJob`.** Tourne toutes les 2 heures sur tous les établissements avec `adresse: nil` et porte un `TODO: remove this job in a few days` depuis son introduction. Il ne déclenche pas de jobs français, donc il n'est pas un risque pour ce chantier — mais en Polynésie, où beaucoup d'établissements ISPF n'ont pas d'adresse, il martèle probablement l'API i-taiete en permanence pour rien. À traiter dans un chantier distinct.
