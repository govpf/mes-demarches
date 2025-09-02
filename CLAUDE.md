# Documentation Projet mes-demarches

## Vue d'ensemble du projet

**mes-demarches** est un fork de [demarches-simplifiees.fr](https://github.com/demarches-simplifiees/demarches-simplifiees.fr) adapté aux besoins spécifiques de la Polynésie française.

### But du projet
Ce projet permet aux administrations publiques de créer des démarches administratives dématérialisées. Les citoyens peuvent ainsi effectuer leurs démarches en ligne de manière simplifiée, tandis que les agents publics disposent d'outils pour instruire et traiter ces demandes.

### Différences avec demarches-simplifiees.fr
Les adaptations pour la Polynésie française incluent :
- Champs spécifiques au territoire (communes de Polynésie, codes postaux, numéros DN, etc.)
- Intégration d'authentification locale (Tatou, Microsoft pour les agents publics)
- Adaptations géographiques et réglementaires
- Interface adaptée aux spécificités locales

> **📋 Documentation des spécificités** : Voir [french_polynesia.md](./french_polynesia.md) pour le détail complet des différences fonctionnelles et techniques.

## Modèle de données principal

Le système repose sur quatre entités centrales qui forment la colonne vertébrale de l'application :

### 1. **Procedure** (`app/models/procedure.rb`)
Une procédure représente un type de démarche administrative (ex: "Demande de permis de construire").
- **Identifiants** : `id`, `path` (URL publique)
- **Métadonnées** : `libelle`, `description`, `service`, `cadre_juridique`
- **États** : `brouillon`, `publiee`, `close`, `depubliee`
- **Relations** : Une procédure a plusieurs révisions

### 2. **Revision** (`app/models/revision.rb`)
Une révision représente une version figée de la structure d'une procédure.
- **Principe** : Chaque modification de la structure crée une nouvelle révision
- **Versionning** : Permet de maintenir la cohérence des dossiers en cours
- **Relations** : 
  - Appartient à une procédure
  - Lie des types de champs via `ProcedureRevisionTypeDeChamp`

### 3. **TypeDeChamp** (`app/models/type_de_champ.rb`)
Définit la structure et les propriétés d'un champ de formulaire.
- **Propriétés** : `libelle`, `description`, `type_champ`, `options`, `mandatory`
- **Identifiant stable** : `stable_id` (invariant entre révisions)
- **Types disponibles** : texte, nombre, date, pièce jointe, visa, etc.
- **Configuration** : Stockage JSON des options spécifiques par type

### 4. **Champ** (`app/models/champ.rb`)
Instance concrète d'un champ avec sa valeur pour un dossier spécifique.
- **Données** : `value`, `data`, `external_id`
- **Relations** : 
  - Appartient à un dossier
  - Référence un `TypeDeChamp` via `stable_id`
- **Héritage** : Classes spécialisées dans `app/models/champs/`

### 5. **Dossier** (`app/models/dossier.rb`)
Représente une demande concrète d'un usager pour une procédure.
- **Cycle de vie** : `en_construction`, `en_instruction`, `accepte`, `refuse`, etc.
- **Acteurs** : `user` (demandeur), `instructeurs` (agents traitants)
- **Contenu** : Collection de champs remplis par l'usager

### Relations et flux de données

```
Procedure (1) ──→ (n) Revision ──→ (n) ProcedureRevisionTypeDeChamp ──→ (1) TypeDeChamp
                                                                              ↑
Dossier (1) ──→ (n) Champ ──────────────────────────────────────────────────┘
                                                                    (via stable_id)
```

**Exemple concret** :
1. Un administrateur crée une procédure "Demande de subvention"
2. Il ajoute des types de champs (nom, montant, justificatifs) → Révision v1
3. Un usager remplit un dossier → Création de champs liés aux TypeDeChamp
4. L'administrateur modifie la procédure (ajoute un champ) → Révision v2
5. Les nouveaux dossiers utilisent v2, les anciens restent sur v1

## Environnement

- Ruby 3.3.2
- Rails 7.0.8.4
- PostgreSQL
- WSL2 Linux

## Architecture des Champs et Types de Champs

### Modèles principaux

1. **TypeDeChamp** (`app/models/type_de_champ.rb`)
   - Définit la structure d'un champ (libellé, type, options, etc.)
   - Contient les types disponibles dans `INSTANCE_TYPE_CHAMPS` et `enum type_champs`
   - Stocke les options dans un attribut JSON avec `store_accessor :options`
   - Méthodes utiles : `visa?`, `table_row_selector?`, `accredited_user_list`, etc.

2. **Champs** (`app/models/champs/`)
   - Instances concrètes des champs avec leurs valeurs
   - Héritent de `Champs::TextChamp` ou autres classes de base
   - Exemple : `Champs::TableRowSelectorChamp`, `Champs::VisaChamp`
   - Stockent les données dans les attributs `value`, `data`, `external_id`

3. **Révisions et Procédures**
   - Une `Procedure` a plusieurs `Revision`
   - Une `Revision` lie des `TypeDeChamp` via `ProcedureRevisionTypeDeChamp`
   - Les `Champs` sont liés à un `TypeDeChamp` via son `stable_id`

### Hiérarchie des types

```ruby
# Dans TypeDeChamp
CATEGORIES = [STRUCTURE, ETAT_CIVIL, LOCALISATION, PAIEMENT_IDENTIFICATION, STANDARD, PIECES_JOINTES, CHOICE, REFERENTIEL_EXTERNE]

# Exemple de catégorisation
TYPE_DE_CHAMP_TO_CATEGORIE = {
  table_row_selector: REFERENTIEL_EXTERNE,
  visa: STRUCTURE,
  text: STANDARD,
  # ...
}
```

### Système de types dynamiques

Chaque `TypeDeChamp` a un `dynamic_type` correspondant :
- `TypesDeChamp::TextTypeDeChamp`
- `TypesDeChamp::TableRowSelectorTypeDeChamp`
- etc.

Ces classes gèrent la logique spécifique (validation, rendu, etc.)

### API GraphQL

1. **Types pour les Champs** (`app/graphql/types/champs/`)
   - `ChampType` : interface de base pour tous les champs
   - `TextChampType`, `TableRowSelectorChampType`, etc.
   - Résolution automatique dans `ChampType.resolve_type`

2. **Types pour les Descripteurs** (`app/graphql/types/champs/descriptor/`)
   - `ChampDescriptorType` : interface pour décrire la structure des champs
   - `TextChampDescriptorType`, `TableRowSelectorChampDescriptorType`, etc.
   - Résolution dans `ChampDescriptorType.resolve_type`

3. **Processus d'ajout d'un nouveau type**
   - Ajouter le type dans `TypeDeChamp.type_champs`
   - Créer la classe `Champs::XxxChamp`
   - Créer la classe `TypesDeChamp::XxxTypeDeChamp`
   - Créer `Types::Champs::XxxChampType` (GraphQL)
   - Créer `Types::Champs::Descriptor::XxxChampDescriptorType` (GraphQL)
   - Ajouter les résolutions dans `ChampType` et `ChampDescriptorType`
   - Régénérer le schéma GraphQL avec `bin/rails graphql:schema:dump`

### Exemple concret : TableRowSelector

```ruby
# Type enum
table_row_selector: 'table_row_selector'

# Classe du champ
class Champs::TableRowSelectorChamp < Champs::TextChamp
  def value
    external_id  # Pour l'API GraphQL
  end
end

# Type GraphQL du champ
class Types::Champs::TableRowSelectorChampType < Types::BaseObject
  implements Types::ChampType
  
  field :columns, [TableColumnType], null: false
  # ...
end

# Type GraphQL du descripteur
class Types::Champs::Descriptor::TableRowSelectorChampDescriptorType < Types::BaseObject
  implements Types::ChampDescriptorType
  # Propriétés de configuration du champ
end
```

### Gestion des options

Les options sont stockées dans `TypeDeChamp.options` (JSON) :
- `accredited_users` : liste des emails pour les visas
- `table_id` : ID de la table externe pour table_row_selector
- `drop_down_options` : options pour les listes déroulantes
- etc.

Accès via `store_accessor :options, :accredited_users, :table_id, ...`

### Problème des emails vs IDs pour les visas

Le champ `visa` utilise `accredited_users` (array d'emails) pour définir qui peut cocher le visa.
**Problème** : si l'email d'un utilisateur change, la configuration devient obsolète.

**Solutions envisagées** :
1. **Nouvelle colonne** : `accredited_user_ids` + fallback sur emails
2. **Résolution automatique** : email → user_id au runtime  
3. **Migration transparente** : table de mapping email ↔ user_id

## Commandes utiles

- Régénérer le schéma GraphQL : `bin/rails graphql:schema:dump`
- Lancer les tests GraphQL : `bundle exec rspec spec/controllers/api/v2/graphql_controller_spec.rb`

## Processus de Release

### Étapes pour créer une release

#### 1. Préparation et vérification
* S'assurer d'être sur la branche masterpf
* Identifier le dernier tag pf-AAAA-MM-JJ depuis `.git/refs/tags/`
* Analyser les commits depuis ce tag via `.git/logs/refs/heads/masterpf`

#### 2. Identification des releases upstream intégrées
* **CRITIQUE** : Identifier précisément quelle(s) release(s) upstream ont été intégrées
* Les noms des releases upstream sont de la forme `AAAA-MM-JJ-NN` (ex: 2024-10-17-01)
* Récupérer le contenu exact de ces releases depuis https://github.com/demarches-simplifiees/demarches-simplifiees.fr/releases/tag/AAAA-MM-JJ-NN
* **NE PAS** inclure d'éléments de releases postérieures à celle intégrée

#### 3. Structure du texte de release (format obligatoire)
* Titre : `# Release pf-AAAA-MM-JJ`
* Section : `## Améliorations et correctifs`
* Sous-section upstream : `### Intégration de la release upstream AAAA-MM-JJ-NN`
* Chapitres exacts : `#### Administrateur`, `#### Instructeur`, `#### Usager`, `#### API`, `#### Technique`
* **COPIER EXACTEMENT** le texte, numéros d'issues (#NNNN), et format "ETQ" des releases upstream
* Sous-section PF : `### Polynésie`
* Chapitre PF technique : `#### Technique`

#### 4. Contenu spécifique Polynésie
* **Sémantiquement intéressant uniquement** : nouvelles fonctionnalités utilisateur, corrections importantes
* **Détails techniques de maintenance** → chapitre Technique
* Format : liste à puces avec descriptions concises
* Maintien des spécificités : champs DN, communes PF, codes postaux, nationalités, TeFeNua, Visa, authentification (Tatou, Microsoft), GraphQL étendu

#### 5. Migrations (si applicable)
* Section `## Migrations` avec liste des migrations ajoutées
* Format : `- NomDeLaMigration : description`

#### 6. Création de la release GitHub
```bash
# Créer le tag local
git tag -a pf-AAAA-MM-JJ -m "Release pf-AAAA-MM-JJ"

# Créer la GitHub release avec titre et notes formatées
gh release create pf-AAAA-MM-JJ --title "JJ MMM AAAA" --notes "$(cat <<'EOF'
## Améliorations et correctifs

### Intégration de la release upstream AAAA-MM-JJ-NN

[CONTENU COMPLET DE LA RELEASE]
EOF
)"
```

#### 7. Vérification
* Vérifier le tag local : `git tag -l pf-AAAA-MM-JJ`
* Vérifier sur GitHub : https://github.com/govpf/mes-demarches/releases

### Erreurs critiques à éviter
* **NE JAMAIS** mélanger des éléments de plusieurs releases upstream
* **NE JAMAIS** inventer ou modifier les numéros d'issues upstream
* **TOUJOURS** respecter le chapitrage exact : Administrateur, Instructeur, Usager, API, Technique
* **TOUJOURS** utiliser le format "ETQ" (En Tant Que) des releases upstream
* **VÉRIFIER** que la release upstream identifiée correspond bien aux commits intégrés
## Procédure de Nettoyage du Code

### Suppression du Code lié au TableRowSelector après Premier Déploiement

- Après le premier déploiement réussi, suivre ces étapes précises pour supprimer le code lié au tableRowSelector :
  1. Supprimer les fichiers spécifiques à `table_row_selector` dans les répertoires :
     - `app/models/champs/table_row_selector_champ.rb`
     - `app/graphql/types/champs/table_row_selector_champ_type.rb`
     - `app/graphql/types/champs/descriptor/table_row_selector_champ_descriptor_type.rb`
  
  2. Retirer les références dans `app/models/type_de_champ.rb` :
     - Supprimer l'entrée `table_row_selector` de l'enum `type_champs`
     - Retirer toute logique conditionnelle liée à `table_row_selector`
  
  3. Nettoyer les migrations et seeds :
     - Supprimer toute migration qui ajoute des colonnes ou configurations spécifiques à `table_row_selector`
     - Retirer les références dans les fichiers de seed/fixtures
  
  4. Mise à jour des tests et specs :
     - Supprimer les tests unitaires et d'intégration liés à `table_row_selector`
     - Ajuster les fixtures et factories de test

  5. Vérifications finales :
     - Lancer la suite de tests complète pour s'assurer de l'absence de régressions
     - Valider que GraphQL ne référence plus le type `table_row_selector`

## Intégration Upstream

### Vue d'ensemble

L'intégration des releases upstream de [demarches-simplifiees.fr](https://github.com/demarches-simplifiees/demarches-simplifiees.fr) nécessite une approche méthodique pour maintenir les spécificités PF tout en bénéficiant des améliorations upstream.

### Processus d'intégration

#### 1. **Préparation**
```bash
# Créer une branche dédiée depuis devpf
git checkout devpf
git pull origin devpf
git checkout -b feature/bump-AAAA-MM-JJ

# Identifier la release upstream à intégrer
git fetch upstream
git tag -l "2024-*" | sort -V | tail -5
```

#### 2. **Intégration du tag upstream**
```bash
# Merger le tag upstream
git merge upstream/AAAA-MM-JJ-NN

# Pour les locales : prendre upstream systématiquement
git checkout --theirs config/locales/
```

#### 3. **Stratégie des tags PF**

**🏷️ Principe fondamental :**
Tous les comportements spécifiques à la Polynésie française doivent être marqués par des commentaires `# pf:` dans le code.

**Résolution de conflits :**
1. **Chercher les tags `# pf:` voisins** pour comprendre le contexte de la spécificité
2. **Si tag PF présent** : analyser si la spécificité doit être maintenue
3. **Si aucun tag PF** : prendre la version upstream par défaut

**Exemples de tags PF :**
```ruby
# pf: support OpenID providers (Tatou, Microsoft) en plus de France Connect
def send_custom_confirmation_instructions(provider_type: :france_connect)

# pf: harmonisation avec France Connect pour maintenir la cohérence UX
def sanitize(string)

# pf: champs spécifiques Polynésie (DN, communes PF, codes postaux)
validates :numero_dn, format: { with: /\A\d{8}\z/ }
```

#### 4. **Tests et corrections**

**🧪 Tests critiques PF à vérifier :**
```bash
# Tests authentification spécifique
bundle exec rspec spec/controllers/omniauth_controller_spec.rb

# Tests champs PF
bundle exec rspec spec/models/champs/ -e "DN|Commune"

# Tests API GraphQL  
bundle exec rspec spec/controllers/api/v2/graphql_controller_spec.rb
```

**🔧 Corrections typiques :**
- Messages de validation changés → corriger les expectations des tests
- Nouvelles règles de linting → `bundle exec rubocop -A`
- Conflits de traductions → prendre upstream pour les locales

### Bonnes pratiques

#### **🎯 Stratégie de merge**
- **Une release à la fois** : Ne jamais merger plusieurs releases
- **Branche dédiée** : `feature/bump-AAAA-MM-JJ`  
- **Tags PF systématiques** : Marquer toute spécificité dans le code
- **CI rapide** : Pousser tôt pour avoir le feedback

#### **⚠️ Points de vigilance**
- **Champs PF** : DN, communes, codes postaux, nationalités
- **Authentification** : Tatou, Microsoft, workflows de merge  
- **Templates** : Personnalisations email PF à préserver
- **Migrations** : Adaptations pour les données PF

### Checklist de validation

#### **✅ Avant le push**
- [ ] Tous les tests passent : `bundle exec rspec`
- [ ] Linting OK : `bundle exec rails lint`
- [ ] Tags `# pf:` ajoutés sur les spécificités
- [ ] Pas de régression des fonctionnalités PF

#### **✅ Après intégration**
- [ ] CI verte sur tous les environnements
- [ ] Tests manuels des fonctionnalités PF
- [ ] Release notes rédigées
