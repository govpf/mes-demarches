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

- Ruby 3.3.1
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
* S'assurer d'etre sur la branche masterpf. 
* regarder les deux dernières releases de Mes-Démarches pour comprendre la structure
* déterminer tous les commits depuis le dernier tag pf-XXX 
* identifier dans ces commits les releases upstream qui ont été intégrées
* les fusionner en gardant exactement le texte, les ids des users stories mais en fusionnant les chapitres pour créer la base de la release
* déterminer dans ces commits les modifications apportées en Polynésie et enrichir la release avec ces informations
* Vérifier et ajuster éventuellement le texte de la release pour respecter la philosophie des deux dernière releases Mes-Démarches
* proposer cette release pour validation.