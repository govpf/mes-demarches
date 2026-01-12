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
   - Exemple : `Champs::ReferentielDePolynesieChamp`, `Champs::VisaChamp`
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
- `TypesDeChamp::ReferentielDePolynesieTypeDeChamp`
- etc.

Ces classes gèrent la logique spécifique (validation, rendu, etc.)

### API GraphQL

1. **Types pour les Champs** (`app/graphql/types/champs/`)
   - `ChampType` : interface de base pour tous les champs
   - `TextChampType`, `ReferentielDePolynesieChampType`, etc.
   - Résolution automatique dans `ChampType.resolve_type`

2. **Types pour les Descripteurs** (`app/graphql/types/champs/descriptor/`)
   - `ChampDescriptorType` : interface pour décrire la structure des champs
   - `TextChampDescriptorType`, `ReferentielDePolynesieChampDescriptorType`, etc.
   - Résolution dans `ChampDescriptorType.resolve_type`

3. **Processus d'ajout d'un nouveau type**
   - Ajouter le type dans `TypeDeChamp.type_champs`
   - Créer la classe `Champs::XxxChamp`
   - Créer la classe `TypesDeChamp::XxxTypeDeChamp`
   - Créer `Types::Champs::XxxChampType` (GraphQL)
   - Créer `Types::Champs::Descriptor::XxxChampDescriptorType` (GraphQL)
   - Ajouter les résolutions dans `ChampType` et `ChampDescriptorType`
   - Régénérer le schéma GraphQL avec `bin/rails graphql:schema:dump`

### Exemple concret : ReferentielDePolynesie

```ruby
# Type enum
referentiel_de_polynesie: 'referentiel_de_polynesie'

# Classe du champ
class Champs::ReferentielDePolynesieChamp < Champs::TextChamp
  def value
    external_id  # Pour l'API GraphQL
  end
end

# Type GraphQL du champ
class Types::Champs::ReferentielDePolynesieChampType < Types::BaseObject
  implements Types::ChampType
  
  field :columns, [TableColumnType], null: false
  # ...
end

# Type GraphQL du descripteur
class Types::Champs::Descriptor::ReferentielDePolynesieChampDescriptorType < Types::BaseObject
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

⚠️ **PIÈGE MAJEUR** : Une PR `feature/bump-AAAA-MM-JJ-NN` peut contenir **PLUSIEURS** releases upstream, et la description de la PR peut être **incomplète** !

**Méthode correcte (OBLIGATOIRE) :**

```bash
# Étape 1: Identifier toutes les PRs feature/bump-* depuis le dernier tag PF
git log pf-AAAA-MM-DD..HEAD --merges --oneline | grep -E "Feature/bump"

# Exemple de sortie :
# 146364e1d4 Feature/bump 2025 04 30 01 (#231)
# e97c6d4392 Feature/bump 2025 04 23 01 (#229)

# Étape 2: Pour CHAQUE PR identifiée, lire sa description
gh pr view 229 --json body --jq '.body'

# Exemple de sortie :
# [Release du 2025-04-16-01](https://github.com/...)
# [Release du 2025-04-16-02](https://github.com/...)
# [Release du 2025-04-17-01](https://github.com/...)
# [Release du 2025-04-23-01](https://github.com/...)

# ⚠️ ATTENTION : La description peut être incomplète !

# Étape 3: VÉRIFICATION MANUELLE obligatoire du contenu réel de la PR
# Récupérer le hash du merge commit de la PR
PR_MERGE_COMMIT=$(git log --merges --oneline --grep="#229" | head -1 | awk '{print $1}')

# Examiner les commits de la PR (entre le parent et le merge)
git log ${PR_MERGE_COMMIT}^..${PR_MERGE_COMMIT}^2 --oneline | grep "Merge pull request" | head -20

# Comparer avec les releases upstream de la période pour identifier les manquantes
gh release list --repo demarches-simplifiees/demarches-simplifiees.fr --limit 50 | grep "2025-04"

# Étape 4: Pour CHAQUE release upstream identifiée, récupérer son contenu
gh release view 2025-04-16-01 --repo demarches-simplifiees/demarches-simplifiees.fr
gh release view 2025-04-16-02 --repo demarches-simplifiees/demarches-simplifiees.fr
# etc.
```

**⚠️ Erreurs critiques à éviter lors de l'identification :**

1. **Se fier uniquement à la description de la PR** → Peut être incomplète
   - ❌ Erreur : PR #229 listait 4 releases mais en contenait 5
   - ✅ Solution : Toujours vérifier manuellement le contenu réel de la PR

2. **Chercher uniquement "Merge tag" dans les commits** → Rate les releases intégrées via d'autres chemins
   - ❌ Erreur : `git log | grep "Merge tag"` ne trouve pas toutes les releases
   - ✅ Solution : Examiner tous les merge commits dans chaque PR

3. **Inclure des releases déjà présentes dans le tag PF précédent** → Duplication
   - ❌ Erreur : Inclure 2025-04-10-01 qui était déjà dans pf-2025-12-04
   - ✅ Solution : Vérifier le contenu du tag PF précédent :
     ```bash
     gh release view pf-2025-12-04 --json body --jq '.body' | grep "2025-04-10"
     ```

4. **Oublier de vérifier la continuité des releases** → Trous dans la séquence
   - ❌ Erreur : Avoir 2025-04-16-01, sauter 2025-04-16-02, puis 2025-04-17-01
   - ✅ Solution : Lister chronologiquement toutes les releases upstream intégrées

**Checklist de validation de l'identification :**
- [ ] Toutes les PRs feature/bump-* depuis le dernier tag PF ont été examinées
- [ ] Pour chaque PR, le contenu réel (pas juste la description) a été vérifié
- [ ] Aucune release upstream n'est en doublon avec le tag PF précédent
- [ ] Les releases sont listées dans l'ordre chronologique
- [ ] Aucun "trou" dans la séquence des releases (ex: -01, -02, -03)

**Exemple réel de piège évité :**
- Tag précédent : pf-2025-12-04
- PR #229 s'appelle "Feature/bump 2025 04 23 01" → Laisse penser qu'elle contient 1 release
- En réalité, elle contenait 5 releases : 2025-04-16-01, -02, 2025-04-17-01, 2025-04-23-01, **2025-04-24-01**
- La 5ème (2025-04-24-01) n'était **pas listée** dans la description de la PR !
- Méthode correcte : `git log <pr>^..<pr>^2` a révélé tous les merge commits upstream

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

⚠️ **IMPORTANT** : Laisser GitHub créer le tag automatiquement. Ne PAS créer de tag local avant, sinon il faudra le pousser et cela cause des erreurs avec `gh release create`.

```bash
# Créer la GitHub release (elle créera le tag automatiquement)
gh release create pf-AAAA-MM-JJ --title "JJ MMM AAAA" --notes "$(cat <<'EOF'
## Améliorations et correctifs

### Intégration de la release upstream AAAA-MM-JJ-NN

[CONTENU COMPLET DE LA RELEASE]
EOF
)"
```

#### 7. Vérification
* Vérifier sur GitHub : https://github.com/govpf/mes-demarches/releases
* Le tag sera automatiquement créé et visible dans `.git/refs/tags/`

### Erreurs critiques à éviter

#### Lors de l'identification des releases
* **NE JAMAIS** se fier uniquement à la description de la PR (peut être incomplète)
* **NE JAMAIS** utiliser uniquement `git log | grep "Merge tag"` (rate des releases)
* **TOUJOURS** vérifier manuellement le contenu réel de chaque PR avec `git log <pr>^..<pr>^2`
* **TOUJOURS** vérifier qu'une release n'est pas déjà dans le tag PF précédent (éviter les doublons)
* **VÉRIFIER** la continuité chronologique des releases (pas de trous dans la séquence)

#### Lors de la rédaction
* **NE JAMAIS** mélanger des éléments de plusieurs releases upstream dans une même section
* **NE JAMAIS** inventer ou modifier les numéros d'issues upstream
* **TOUJOURS** respecter le chapitrage exact : Administrateur, Instructeur, Usager, API, Technique
* **TOUJOURS** utiliser le format "ETQ" (En Tant Que) des releases upstream
* **COPIER EXACTEMENT** le texte des releases upstream (y compris la ponctuation et les fautes)

### Exemple complet pas-à-pas

**Contexte :** Créer la release pf-2025-12-05 depuis le dernier tag pf-2025-12-04

```bash
# 1. Identifier les PRs feature/bump-* mergées
git log pf-2025-12-04..HEAD --merges --oneline | grep "Feature/bump"
# Résultat :
# 146364e1d4 Feature/bump 2025 04 30 01 (#231)
# e97c6d4392 Feature/bump 2025 04 23 01 (#229)

# 2. Examiner la PR #229
gh pr view 229 --json body --jq '.body'
# Résultat : Liste 4 releases (2025-04-16-01, -02, 2025-04-17-01, 2025-04-23-01)

# 3. Vérifier le contenu réel de la PR #229 (CRUCIAL !)
PR_MERGE=$(git log --merges --oneline --grep="#229" | head -1 | awk '{print $1}')
git log ${PR_MERGE}^..${PR_MERGE}^2 --oneline | grep "Merge pull request"
# ⚠️ Découverte : Contient aussi 2025-04-24-01 (non listé dans la description !)

# 4. Examiner la PR #231
gh pr view 231 --json body --jq '.body'
# Résultat : Aucune liste (description vide) → Examiner manuellement
PR_MERGE=$(git log --merges --oneline --grep="#231" | head -1 | awk '{print $1}')
git log ${PR_MERGE}^..${PR_MERGE}^2 --oneline | grep "Merge tag"
# Résultat : Contient 2025-04-30-01

# 5. Vérifier qu'aucune de ces releases n'est déjà dans pf-2025-12-04
gh release view pf-2025-12-04 --json body --jq '.body' | grep -E "2025-04-(16|17|23|24|30)"
# Résultat : Aucune correspondance → OK, aucune duplication

# 6. Lister chronologiquement toutes les releases identifiées
# - 2025-04-16-01
# - 2025-04-16-02
# - 2025-04-17-01
# - 2025-04-23-01
# - 2025-04-24-01
# - 2025-04-30-01

# 7. Récupérer le contenu de CHAQUE release
for release in 2025-04-16-01 2025-04-16-02 2025-04-17-01 2025-04-23-01 2025-04-24-01 2025-04-30-01; do
  echo "=== $release ==="
  gh release view $release --repo demarches-simplifiees/demarches-simplifiees.fr
done

# 8. Rédiger la release en copiant exactement le contenu de chaque release upstream

# 9. Créer la release GitHub
gh release create pf-2025-12-05 --title "5 Déc 2025" --notes "$(cat release_notes.md)"
```

**Résultat :** Release complète avec les 6 releases upstream correctement identifiées et documentées.

## Procédure de Nettoyage du Code

### Migration TableRowSelector vers ReferentielDePolynesie

**✅ Migration terminée** : Le type `table_row_selector` a été complètement remplacé par `referentiel_de_polynesie`.

**Changements effectués** :
- Remplacement de `Champs::TableRowSelectorChamp` par `Champs::ReferentielDePolynesieChamp`
- Migration des types GraphQL vers `ReferentielDePolynesieChampType`
- Suppression de l'enum `table_row_selector` au profit de `referentiel_de_polynesie`
- Nettoyage des controllers, components et API Baserow
- Mise à jour des routes et schémas GraphQL

**Vérifications de sécurité** :
- Lancer la suite de tests : `bundle exec rspec`
- Valider GraphQL : `bin/rails graphql:schema:dump`
- S'assurer que les procédures existantes fonctionnent toujours

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

# ⚠️ NE JAMAIS utiliser --theirs ou --ours globalement !
# Cela masque les vrais conflits et peut écraser du code important
```

**❌ À NE JAMAIS FAIRE :**
```bash
git checkout --theirs config/locales/  # ❌ Cache les conflits, peut régresser
git checkout --theirs app/             # ❌ Peut perdre du code PF
git merge --strategy-option theirs     # ❌ Dangereux
```

**✅ Approche correcte :**
- Résoudre **chaque conflit manuellement** en examinant le contexte
- Utiliser les tags `# pf:` pour identifier les spécificités à préserver
- Pour les locales : vérifier si des traductions PF doivent être gardées

#### 3. **Stratégie des tags PF**

**🏷️ Principe fondamental :**
Tous les comportements spécifiques à la Polynésie française doivent être marqués par des commentaires `# pf:` dans le code.

**Résolution de conflits :**
1. **Chercher les tags `# pf:` voisins** pour comprendre le contexte de la spécificité
2. **Si tag PF présent** : analyser si la spécificité doit être maintenue
3. **Si aucun tag PF** : privilégier upstream **SAUF si cela casse une fonctionnalité PF**
4. **En cas de doute** : tester localement ou demander validation

**⚠️ Règle d'or** : Upstream est prioritaire **tant que cela ne remet pas en cause les développements PF**. Si un changement upstream impacte une fonctionnalité PF (même sans tag `# pf:`), il faut adapter intelligemment, pas simplement prendre upstream.

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
- Conflits de traductions → examiner si PF a des spécificités avant de prendre upstream

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
- Tous les messages et texte en français à destination de l'interface doivent utiliser la quote française "'" au lieu d'une quote normale "'". Les tests sur l'interface doivent donc ausi utiliser cette quote française.

### Stratégie alternative : Cherry-pick pour PRs cascadées

#### **📌 Contexte du problème**

Lorsque les PRs sont construites en cascade (PR X basée sur PR Y basée sur PR Z), et que devpf évolue entre temps, les PRs héritent de code obsolète de leur base.

**Exemple** : Si devpf supprime `table_row_selector` entre la création de PR Y et PR Z, alors PR Z contiendra toujours `table_row_selector` car elle est basée sur PR Y qui date d'avant la suppression.

#### **✅ Solution : Cherry-pick pour reconstruire proprement**

Au lieu de merger, **cherry-picker uniquement les commits spécifiques à la PR** depuis le devpf actuel.

**Étapes** :

```bash
# 1. Identifier le point de divergence (dernier commit de la PR précédente mergée dans devpf)
git log devpf --oneline | grep "PR #222"  # Trouver le dernier commit de la PR précédente
DIVERGENCE_POINT="a81e14ddd6"  # Hash du dernier commit de PR #222 dans devpf

# 2. Identifier les commits à cherry-picker
git log ${DIVERGENCE_POINT}..origin/feature/bump-2025-04-03-01 --oneline --no-merges

# 3. Créer une nouvelle branche depuis devpf actuel
git checkout devpf
git pull origin devpf
git checkout -b feature/bump-2025-04-03-01-clean

# 4. Cherry-picker les commits (SANS les merge commits)
git log ${DIVERGENCE_POINT}..origin/feature/bump-2025-04-03-01 --oneline --no-merges --reverse | \
  awk '{print $1}' | \
  while read commit; do
    git cherry-pick $commit || echo "Conflict or empty commit: $commit"
  done

# 5. Gérer les commits vides ou conflits
# - Skip empty commits : git cherry-pick --skip
# - Résoudre conflits manuellement
# - Utiliser --ours pour Gemfile.lock, régénérer à la fin
```

#### **⚠️ WARNINGS CRITIQUES**

##### 1. **Commits "empty" perdus**

**Problème** : Un commit peut devenir "empty" si son contexte a changé dans devpf.

**Exemple vécu (PR #256)** :
- Commit upstream `0e74d8afe4` (2 avril 2025) ajoute `Capybara.page.current_window.resize_to(1440, 900)` dans un test
- Commit PF `390382ac26` (18 novembre 2025) refactorise massivement le même fichier de test
- Lors du cherry-pick : git considère le commit comme "empty" car le contexte n'existe plus
- **Résultat** : Le fix est perdu silencieusement

**Solution** :
```bash
# Après cherry-pick, comparer les fichiers critiques avec upstream
git diff origin/feature/bump-2025-04-03-01 -- spec/system/

# Si des différences importantes apparaissent, investiguer manuellement
```

##### 2. **Tests system particulièrement sensibles**

Les tests Playwright/Capybara sont **très sensibles au contexte** :
- Changements de layout UI
- Modifications de sélecteurs CSS
- Refactorisation de composants React

**Règle** : TOUJOURS lancer les tests system complets après cherry-pick :
```bash
bundle exec rspec spec/system/ --format documentation
```

##### 3. **Validation obligatoire**

Le cherry-pick **n'est PAS magique** :
- ✅ Fonctionne bien pour les commits indépendants
- ❌ Échoue silencieusement quand le contexte change
- ⚠️ Ne garantit PAS la cohérence fonctionnelle

**Checklist de validation cherry-pick** :
- [ ] Tous les unit tests passent : `bundle exec rspec spec/models spec/controllers spec/services`
- [ ] Tous les system tests passent : `bundle exec rspec spec/system`
- [ ] Comparer avec la PR upstream : `git diff origin/feature/original-pr`
- [ ] Tester manuellement les fonctionnalités critiques
- [ ] Vérifier qu'aucun commit n'a été "skippé" silencieusement

#### **🎯 Quand utiliser cherry-pick vs merge**

| Situation | Méthode recommandée |
|-----------|---------------------|
| PR basée directement sur devpf | ✅ Merge classique |
| PR basée sur une autre PR (cascade) | ✅ Cherry-pick |
| devpf a beaucoup évolué depuis la base | ✅ Cherry-pick |
| Première intégration d'un tag upstream | ✅ Merge classique |

#### **📝 Exemple réel : PR #223 → PR #256**

**Contexte** :
- PR #223 basée sur PR #222 (qui elle-même était basée sur PR #221, etc.)
- devpf a évolué : PR #251 mergée entre temps
- Résultat : PR #223 contenait du code obsolète de PR #222

**Solution appliquée** :
1. Cherry-picked 37 commits non-merge de PR #223
2. Résolu les conflits (Gemfile.lock, secrets.yml, etc.)
3. **Découvert** : commit `0e74d8afe4` perdu (test Capybara)
4. **Correction manuelle** : Réappliqué le fix upstream

**Leçon** : Le cherry-pick élimine le code obsolète, mais nécessite une validation approfondie des tests.