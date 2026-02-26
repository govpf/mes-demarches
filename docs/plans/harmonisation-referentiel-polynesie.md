# Plan : Harmonisation `referentiel` et `referentiel_de_polynesie`

## Objectif

Faire bénéficier `referentiel_de_polynesie` (spécifique PF) des fonctionnalités riches de `referentiel` (upstream), notamment le **pré-remplissage automatique**, tout en préservant les spécificités PF (colonnes multi-usager/instructeur, recherche multi-mots, GraphQL).

## Contexte

### Situation actuelle

**`referentiel` (upstream)** :
- ✅ Pré-remplissage automatique via mapping JSONPath
- ✅ Validation robuste avec retry logic
- ✅ Gestion d'erreurs HTTP (codes 429, 500, 503...)
- ❌ Pas d'affichage multi-colonnes
- ❌ Pas de type GraphQL exposé

**`referentiel_de_polynesie` (PF)** :
- ✅ Recherche multi-mots intelligente (AND)
- ✅ Affichage multi-colonnes (usager/instructeur)
- ✅ Export enrichi avec colonnes custom
- ✅ GraphQL complet
- ❌ **Pas de pré-remplissage automatique** ← Manque principal

### Analyse technique

Le code upstream est déjà structuré pour l'extension :
- `Referentiel` est une classe abstraite avec relation `has_many :types_de_champ`
- `ReferentielService` a déjà un `case referentiel` extensible (ligne 22)
- `Champs::ReferentielChamp` implémente tout le mécanisme de pré-remplissage (lignes 71-89)

## Solution : Héritage via `Referentiels::BaserowReferentiel`

### Architecture cible

```ruby
# Upstream (inchangé)
Referentiel (Abstract)
├── Referentiels::APIReferentiel
└── Referentiels::CsvReferentiel

# PF: Nouveau type de Referentiel
└── Referentiels::BaserowReferentiel  # pf: support Baserow pour PF

# Migration du champ PF
Champs::ReferentielDePolynesieChamp < Champs::ReferentielChamp
  # pf: hérite au lieu de TextChamp → bénéficie du pré-remplissage gratuit
```

### Bénéfices

1. **Réutilisation maximale** : 90% du code upstream (pré-remplissage, validation, retry logic)
2. **Conservation des spécificités PF** : Colonnes, GraphQL, recherche multi-mots (via surcharges)
3. **Facilite les intégrations upstream** : Pas de conflit, merge automatique des améliorations
4. **Dette technique minimale** : Pas de duplication de code

## Fichiers à créer

### 1. `/app/models/referentiels/baserow_referentiel.rb` (~80 lignes)

**Rôle** : Adapter Baserow à l'interface `Referentiel` upstream

```ruby
# frozen_string_literal: true

# pf: Support Baserow comme source de données pour les référentiels PF
class Referentiels::BaserowReferentiel < Referentiel
  validates :name, presence: true, uniqueness: true

  store_accessor :options, :table_id

  validates :table_id, presence: true, numericality: { only_integer: true, greater_than: 0 }

  def ready?
    configured? && baserow_config.present?
  end

  def configured?
    table_id.present?
  end

  # pf: Pas de mode exact_match/autocomplete, toujours search multi-mots
  def self.autocomplete_available?
    true
  end

  def self.csv_available?
    false
  end

  # pf: Interface adaptée pour ReferentielService
  def url
    # Format compatible : {id} sera remplacé par external_id
    "baserow://#{table_id}/{id}"
  end

  # pf: Config Baserow pour ce table_id
  def baserow_config
    @baserow_config ||= ReferentielDePolynesie::BaserowAPI.config(table_id)
  end

  # pf: Headers pour l'affichage multi-colonnes
  def headers
    return [] unless baserow_config

    model = ReferentielDePolynesie::BaserowAPI.fields(baserow_config)
    usager_fields = ReferentielDePolynesie::BaserowAPI.field_names(model, baserow_config['Champs usager'])
    instructeur_fields = ReferentielDePolynesie::BaserowAPI.field_names(model, baserow_config['Champs instructeur'])

    (usager_fields + instructeur_fields).uniq
  end
end
```

### 2. `/app/services/referentiels/baserow_service.rb` (~80 lignes)

**Rôle** : Service pour fetch data depuis Baserow (compatible avec l'interface ReferentielService)

```ruby
# frozen_string_literal: true

# pf: Service pour fetch data depuis Baserow (adapté à l'interface ReferentielService)
class Referentiels::BaserowService
  include Dry::Monads[:result]

  attr_reader :referentiel

  def initialize(referentiel:)
    @referentiel = referentiel
  end

  # pf: Compatible avec l'interface ReferentielService.call(external_id)
  def call(external_id)
    result = ReferentielDePolynesie::API.fetch_row(external_id)

    if result.present? && result.is_a?(Hash)
      Success(result)
    else
      Failure(retryable: false, reason: StandardError.new('Row not found'), code: 404)
    end
  rescue StandardError => e
    Failure(retryable: false, reason: e, code: 500)
  end

  # pf: Validation de la config Baserow
  def validate_referentiel
    config = referentiel.baserow_config

    if config.present?
      referentiel.update_column(:last_response, { status: 200, body: config })
      true
    else
      referentiel.update_column(:last_response, { status: 404, body: {} })
      false
    end
  end
end
```

### 3. Migration de données (~30 lignes)

**Rôle** : Créer des `Referentiels::BaserowReferentiel` pour chaque `table_id` unique et lier les TypeDeChamp

```ruby
class MigrateReferentielDePolynesieToBaserowReferentiel < ActiveRecord::Migration[7.0]
  def up
    # pf: Créer un Referentiels::BaserowReferentiel pour chaque table_id unique
    TypeDeChamp.where(type_champ: :referentiel_de_polynesie).find_each do |tdc|
      next if tdc.table_id.blank?

      # Chercher ou créer le referentiel Baserow
      referentiel = Referentiels::BaserowReferentiel.find_or_create_by(
        name: SecureRandom.uuid, # Générer un nom unique
        table_id: tdc.table_id
      )

      # Lier le TypeDeChamp au referentiel
      tdc.update_column(:referentiel_id, referentiel.id)
    end
  end

  def down
    # Supprimer les liens (on garde les Referentiels pour sécurité)
    TypeDeChamp.where(type_champ: :referentiel_de_polynesie).update_all(referentiel_id: nil)
  end
end
```

## Fichiers à modifier

### 1. `/app/models/champs/referentiel_de_polynesie_champ.rb`

**Changement principal** : Hériter de `ReferentielChamp` au lieu de `TextChamp`

**Avant** :
```ruby
class Champs::ReferentielDePolynesieChamp < Champs::TextChamp
```

**Après** :
```ruby
# pf: Champ Baserow avec pré-remplissage (hérite de ReferentielChamp)
class Champs::ReferentielDePolynesieChamp < Champs::ReferentielChamp
  # pf: Surcharge pour adapter à Baserow

  def fetch_external_data
    Referentiels::BaserowService.new(referentiel:).call(external_id)
  end

  # pf: Surcharge pour gérer le format Baserow
  def todo_map_stuff(data:)
    # Baserow retourne { usager_fields:, instructeur_fields:, row:, external_id: }
    # On conserve tout pour l'affichage multi-colonnes
    data
  end

  # pf: Surcharge pour adapter JSONPath à la structure Baserow
  def extract_value_from_jsonpath(data, jsonpath)
    # Baserow retourne { row: { "Nom" => "Papeete", ... } }
    # JSONPath doit chercher dans data["row"]
    JSONPath.value(data.dig("row").with_indifferent_access, JSONPath.simili_to_jsonpath(jsonpath))
  end

  # Conserver les méthodes spécifiques PF :
  # - referentiel_item_value (colonnes pour tags/exports)
  # - focusable_input_id (ancres d'erreur)
  # - selected_items (React ComboBox)
end
```

**Nouvelle méthode à ajouter dans ReferentielChamp** :
```ruby
# Permettre aux sous-classes de surcharger l'extraction de valeur
def extract_value_from_jsonpath(data, jsonpath)
  JSONPath.value(data.with_indifferent_access, JSONPath.simili_to_jsonpath(jsonpath))
end
```

Puis modifier `propagate_prefill` ligne 75 pour utiliser `extract_value_from_jsonpath` :
```ruby
def propagate_prefill(data)
  type_de_champ.referentiel_mapping_prefillable_with_stable_id.each do |jsonpath, mapping|
    update_prefillable_champ(
      mapping[:prefill_stable_id],
      extract_value_from_jsonpath(data, jsonpath)  # Appel à la méthode surchargeable
    )
  end
end
```

### 2. `/app/services/referentiel_service.rb`

**Changement** : Ajouter le support de `BaserowReferentiel` dans `validate_referentiel`

**Avant (lignes 21-34)** :
```ruby
def validate_referentiel
  case referentiel
  when Referentiels::APIReferentiel
    # ... validation API
  end
end
```

**Après** :
```ruby
def validate_referentiel
  case referentiel
  when Referentiels::APIReferentiel
    # ... validation API existante
  when Referentiels::BaserowReferentiel  # pf: support Baserow
    Referentiels::BaserowService.new(referentiel:).validate_referentiel
  end
end
```

**Changement dans `call`** : Déléguer au bon service

**Avant (lignes 16-19)** :
```ruby
def call(query_params)
  result = API::Client.new.call(url: referentiel.url.gsub('{id}', query_params), timeout: API_TIMEOUT)
  handle_api_result(result)
end
```

**Après** :
```ruby
def call(query_params)
  case referentiel
  when Referentiels::APIReferentiel
    result = API::Client.new.call(url: referentiel.url.gsub('{id}', query_params), timeout: API_TIMEOUT)
    handle_api_result(result)
  when Referentiels::BaserowReferentiel  # pf: support Baserow
    Referentiels::BaserowService.new(referentiel:).call(query_params)
  end
end
```

### 3. `/app/models/types_de_champ/referentiel_de_polynesie_type_de_champ.rb`

**Changements** : Ajouter support mapping pour pré-remplissage (comme `ReferentielTypeDeChamp`)

**Ajouter** :
```ruby
# pf: Support mapping pour pré-remplissage (aligné sur referentiel upstream)
store_accessor :options, :referentiel_mapping

def safe_referentiel_mapping
  Hash(referentiel_mapping).with_indifferent_access
end

def referentiel_mapping_prefillable
  safe_referentiel_mapping.filter { |_jsonpath, mapping_opts| mapping_opts[:prefill] == "1" }
end

def referentiel_mapping_prefillable_with_stable_id
  referentiel_mapping_prefillable.filter { |_jsonpath, mapping_opts| mapping_opts[:prefill_stable_id].present? }
end
```

**Conserver les méthodes existantes** :
- `champ_value_for_tag` (support colonnes custom)
- `paths` (génération dynamique de paths pour exports)
- `fetch_instructeur_fields` (cache 1h)
- `drop_down_other?`

## Tests à créer

### 1. `/spec/models/referentiels/baserow_referentiel_spec.rb` (~150 lignes)

**Tests** :
- Validations (table_id présence, numericité)
- `ready?` et `configured?`
- `baserow_config` (mock API Baserow)
- `headers` (génération depuis config Baserow)
- `url` (format "baserow://table_id/{id}")

### 2. `/spec/services/referentiels/baserow_service_spec.rb` (~200 lignes)

**Tests** :
- `call(external_id)` avec succès (Success)
- `call(external_id)` avec échec (Failure)
- `validate_referentiel` avec config valide
- `validate_referentiel` avec config invalide
- Gestion des exceptions StandardError

### 3. `/spec/models/champs/referentiel_de_polynesie_champ_spec.rb` (ajouter ~200 lignes)

**Tests à ajouter** :
- Pré-remplissage automatique (copier de `referentiel_champ_spec.rb`)
  - Pré-remplissage text → text
  - Pré-remplissage string → integer
  - Pré-remplissage string → decimal
  - Pré-remplissage boolean → checkbox/yes_no
- `extract_value_from_jsonpath` (spécifique Baserow avec `data["row"]`)
- `update_with_external_data!` déclenche `propagate_prefill`

**Tests existants à conserver** :
- `champ_value_for_tag` avec colonnes custom
- `selected_items` pour React ComboBox
- `focusable_input_id`

### 4. `/spec/system/administrateurs/referentiel_de_polynesie_prefill_spec.rb` (~300 lignes)

**Test E2E** :
1. Admin crée une procédure avec champ `referentiel_de_polynesie`
2. Admin configure le mapping de pré-remplissage (réutiliser UI existante de `referentiel`)
3. Admin publie la procédure
4. Usager remplit le champ référentiel
5. Job récupère les données Baserow
6. Champs pré-remplis automatiquement (vérifier valeurs)
7. Indicateur "Donnée remplie automatiquement" affiché

## Étapes d'implémentation

### Phase 1 : Infrastructure (5 jours)

**Jour 1-2** : Créer les classes de base
- [ ] Créer `Referentiels::BaserowReferentiel`
- [ ] Créer `Referentiels::BaserowService`
- [ ] Tests unitaires (validations, config, headers)

**Jour 3** : Modifier `ReferentielService`
- [ ] Ajouter support `BaserowReferentiel` dans `call` et `validate_referentiel`
- [ ] Tests de régression sur `ReferentielService`

**Jour 4** : Modifier `ReferentielChamp` (upstream)
- [ ] Extraire `extract_value_from_jsonpath` (méthode surchargeable)
- [ ] Tests de régression

**Jour 5** : Review et validation
- [ ] Code review interne
- [ ] Vérifier que tous les tests passent

### Phase 2 : Migration du Champ (5 jours)

**Jour 6-7** : Modifier le champ PF
- [ ] Changer héritage : `TextChamp` → `ReferentielChamp`
- [ ] Surcharger `fetch_external_data`, `todo_map_stuff`, `extract_value_from_jsonpath`
- [ ] Conserver méthodes spécifiques PF (selected_items, referentiel_item_value, focusable_input_id)

**Jour 8** : Modifier `TypesDeChamp::ReferentielDePolynesieTypeDeChamp`
- [ ] Ajouter `store_accessor :options, :referentiel_mapping`
- [ ] Ajouter méthodes `referentiel_mapping_prefillable*`
- [ ] Tests unitaires

**Jour 9** : Migration de données
- [ ] Créer migration
- [ ] Script de création des `BaserowReferentiel`
- [ ] Tester sur copie de production

**Jour 10** : Tests du pré-remplissage
- [ ] Copier specs de `ReferentielChamp`
- [ ] Adapter aux spécificités Baserow
- [ ] Vérifier tous les types (text, integer, decimal, boolean)

### Phase 3 : Tests et Validation (4 jours)

**Jour 11** : Tests système E2E
- [ ] Créer procédure avec pré-remplissage
- [ ] Tester workflow complet usager
- [ ] Vérifier affichage multi-colonnes (spécificité PF conservée)
- [ ] Tests GraphQL (types exposés conservés)

**Jour 12** : Tests de performance
- [ ] Benchmark avant/après (temps de récupération)
- [ ] Vérifier cache `instructeur_fields` (1h)
- [ ] Tests de charge (50 champs référentiel simultanés)

**Jour 13** : Validation manuelle
- [ ] Tester sur procédures réelles
- [ ] Vérifier compatibilité avec procédures existantes
- [ ] Tests de régression sur toutes les fonctionnalités PF

**Jour 14** : Documentation et préparation déploiement
- [ ] Mettre à jour `CLAUDE.md` (section Architecture des Champs)
- [ ] Documenter les nouveaux workflows de configuration
- [ ] Plan de rollback documenté

## Vérification End-to-End

### Test manuel complet

1. **Configuration du pré-remplissage** (Admin)
   ```
   - Créer procédure
   - Ajouter champ "referentiel_de_polynesie" (Commune PF)
   - Aller dans config du champ → "Configurer le pré-remplissage"
   - Mapper $.row.code_postal → champ "Code postal" (text)
   - Mapper $.row.archipel → champ "Archipel" (text)
   - Mapper $.row.ile → champ "Île" (text)
   - Publier la procédure
   ```

2. **Remplissage par l'usager**
   ```
   - Créer un dossier
   - Chercher "Papeete" dans le champ Commune
   - Sélectionner "Papeete"
   - Attendre job (polling UI)
   - Vérifier que les champs sont pré-remplis :
     * Code postal = "98714"
     * Archipel = "Iles du Vent"
     * Île = "Tahiti"
   - Vérifier indicateur "Donnée remplie automatiquement"
   ```

3. **Validation GraphQL**
   ```graphql
   query {
     dossier(number: 123) {
       champs {
         ... on ReferentielDePolynesieChamp {
           id
           label
           stringValue
           external_id
           columns {
             name
             value
             type
           }
         }
       }
     }
   }
   ```

4. **Export CSV**
   ```
   - Télécharger export CSV du dossier
   - Vérifier colonnes :
     * Commune = "Papeete"
     * Commune (code_postal) = "98714"
     * Commune (archipel) = "Iles du Vent"
     * Commune (ile) = "Tahiti"
   ```

### Tests automatisés

```bash
# Tests unitaires
bundle exec rspec spec/models/referentiels/baserow_referentiel_spec.rb
bundle exec rspec spec/services/referentiels/baserow_service_spec.rb
bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb
bundle exec rspec spec/models/types_de_champ/referentiel_de_polynesie_type_de_champ_spec.rb

# Tests système
bundle exec rspec spec/system/administrateurs/referentiel_de_polynesie_prefill_spec.rb

# Tests GraphQL
bundle exec rspec spec/controllers/api/v2/graphql_controller_spec.rb -e "ReferentielDePolynesie"

# Suite complète
bundle exec rspec
```

### Vérification de la migration

```ruby
# Console Rails
TypeDeChamp.where(type_champ: :referentiel_de_polynesie).each do |tdc|
  puts "TypeDeChamp #{tdc.id} : table_id=#{tdc.table_id}, referentiel_id=#{tdc.referentiel_id}"
  ref = tdc.referentiel
  puts "  → Referentiel: #{ref.class.name}, ready=#{ref.ready?}"
end
```

## Risques et mitigations

| Risque | Probabilité | Impact | Mitigation |
|--------|------------|--------|-----------|
| **Conflit lors merge upstream** | Moyenne | Moyen | Tags `# pf:` sur toutes les surcharges, tests de régression systématiques |
| **Bug dans pré-remplissage** | Faible | Élevé | Suite de tests exhaustive (unit + E2E), validation manuelle |
| **Performance dégradée** | Très faible | Moyen | Benchmarks avant/après, utiliser le cache existant (1h) |
| **Migration données échoue** | Faible | Élevé | Plan de rollback, tests sur copie production, migration réversible |
| **Incompatibilité avec procédures existantes** | Faible | Élevé | Tests de régression exhaustifs, validation manuelle sur procédures réelles |

## Plan de rollback

En cas de problème critique en production :

1. **Rollback BDD** (si migration exécutée < 1h)
   ```bash
   bin/rails db:rollback
   ```

2. **Désactivation feature flag** (si disponible)
   ```ruby
   Flipper.disable(:referentiel_de_polynesie_prefill)
   ```

3. **Revert code**
   ```bash
   git revert <commit-sha>
   git push origin devpf
   ```

4. **Restauration manuelle** (si migration > 1h)
   ```ruby
   # Console Rails
   TypeDeChamp.where(type_champ: :referentiel_de_polynesie).update_all(referentiel_id: nil)
   ```

## Estimation

- **Complexité** : Moyenne
- **Effort** : 10-14 jours (3 sprints)
- **Code nouveau** : ~600 lignes (classes + services + migration)
- **Code modifié** : ~200 lignes (champ, service, type_de_champ)
- **Tests** : ~1000 lignes (unit + système + GraphQL)
- **Risque** : Moyen (migration de données)
- **Bénéfice** : Très élevé (pré-remplissage automatique complet)

## Notes pour l'implémentation

1. **Tags `# pf:`** : Marquer TOUTES les surcharges et nouveau code PF
2. **Tests de régression** : Lancer la suite complète après chaque modification
3. **Cache Baserow** : Conserver le cache 1h existant (`instructeur_fields`)
4. **GraphQL** : Aucun changement nécessaire (types existants conservés)
5. **UI** : Réutiliser les components upstream existants (`ReferentielPrefillComponent`)
6. **Documentation** : Mettre à jour `CLAUDE.md` avec la nouvelle architecture
