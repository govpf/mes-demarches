# Phase 2 : Nettoyage du dual-mode referentiel_de_polynesie

## Contexte

La phase 1 (branche `feature/harmonisation_des_referentiels`) a mis en place un système dual-mode :
- **Mode upstream** : `referentiel_mapping` + `value_json` + `cast_displayable_values`
- **Mode legacy** : `data['row']` + `instructeur_fields`/`usager_fields` + `fetch_instructeur_fields`

Ce dual-mode garantit la rétro-compatibilité pour les dossiers existants dont les `data` sont encore au format `{ row: { ... }, instructeur_fields: [...] }`.

## Prérequis avant phase 2

1. **La phase 1 est en production** depuis suffisamment longtemps (2-4 semaines)
2. **Tous les TypeDeChamp** `referentiel_de_polynesie` ont un `referentiel_mapping` rempli
   ```ruby
   TypeDeChamp.where(type_champ: 'referentiel_de_polynesie')
     .where("referentiel_mapping IS NULL OR referentiel_mapping = '{}'")
     .count # doit être 0
   ```
3. **Migration des champ.data existants** : tous les `data` au format legacy sont convertis en format plat
   ```ruby
   Champ.joins(:type_de_champ)
     .where(type_de_champ: { type_champ: 'referentiel_de_polynesie' })
     .where("data ? 'row'")
     .count # doit être 0
   ```
4. **Tous les champs ont un value_json** calculé (pour ceux qui ont des données)
   ```ruby
   Champ.joins(:type_de_champ)
     .where(type_de_champ: { type_champ: 'referentiel_de_polynesie' })
     .where.not(data: nil)
     .where(value_json: nil)
     .count # doit être 0
   ```

---

## Étape 0 : Migration des données existantes

**Nouvelle migration** : `MigrateExistingReferentielData`

Convertir tous les `champ.data` legacy en format plat et calculer `value_json` :

```ruby
class MigrateExistingReferentielData < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    Champ.joins(:type_de_champ)
      .where(type_de_champ: { type_champ: 'referentiel_de_polynesie' })
      .where("data ? 'row'")
      .find_each do |champ|
        flat_data = champ.data['row']
        champ.update_columns(
          data: flat_data,
          value_json: champ.cast_displayable_values(flat_data.with_indifferent_access)
        )
      end

    # Calculer value_json pour les champs plats qui n'en ont pas encore
    Champ.joins(:type_de_champ)
      .where(type_de_champ: { type_champ: 'referentiel_de_polynesie' })
      .where.not(data: nil)
      .where(value_json: nil)
      .find_each do |champ|
        champ.update_columns(
          value_json: champ.cast_displayable_values(champ.data.with_indifferent_access)
        )
      end
  end
end
```

---

## Étape 1 : Supprimer `normalized_data` et le support du format `row`

**Fichier** : `app/models/champs/referentiel_de_polynesie_champ.rb`

- Supprimer la méthode `normalized_data`
- Simplifier `referentiel_item_value` :
  ```ruby
  # Avant (dual-mode)
  def referentiel_item_value(path)
    normalized_data&.dig(path.to_s)
  end

  # Après
  def referentiel_item_value(path)
    data&.dig(path.to_s)
  end
  ```

**Specs** : supprimer le contexte `'with legacy row format'` dans `referentiel_de_polynesie_champ_spec.rb`

---

## Étape 2 : Supprimer `fetch_external_data_legacy`

**Fichier** : `app/models/champs/referentiel_de_polynesie_champ.rb`

- Supprimer la méthode `fetch_external_data_legacy`
- Supprimer le override `fetch_external_data` (le parent `ReferentielChamp#fetch_external_data` via `super` suffit)
  ```ruby
  # Supprimer tout ça :
  def fetch_external_data
    referentiel.present? ? super : fetch_external_data_legacy
  end

  def fetch_external_data_legacy
    # ...
  end
  ```

**Prérequis** : vérifier que tous les TypeDeChamp ont un `referentiel_id` non nil :
```ruby
TypeDeChamp.where(type_champ: 'referentiel_de_polynesie', referentiel_id: nil).count # doit être 0
```

---

## Étape 3 : Supprimer `fetch_instructeur_fields` et le fallback legacy dans paths/tags

**Fichier** : `app/models/types_de_champ/referentiel_de_polynesie_type_de_champ.rb`

- Supprimer `fetch_instructeur_fields` et `fetch_instructeur_fields_from_baserow`
- Simplifier `paths` : ne garder que le mode upstream (`referentiel_mapping_displayable_for_instructeur`)
  ```ruby
  # Avant (dual-mode)
  def paths
    paths = super
    mapping = referentiel_mapping_displayable_for_instructeur
    if mapping.present?
      # ... upstream mode ...
      return paths
    end
    # Fallback legacy
    instructeur_fields = fetch_instructeur_fields
    # ...
  end

  # Après
  def paths
    paths = super
    referentiel_mapping_displayable_for_instructeur.each do |jsonpath, opts|
      column = opts[:libelle] || jsonpath.delete_prefix('$.')
      paths << {
        libelle: "#{libelle} (#{column})",
        description: "#{description} (#{column})",
        path: column.to_sym,
        maybe_null: public? && !mandatory?
      }
    end
    paths
  end
  ```

- Simplifier `champ_value_for_tag` : ne garder que `value_json`
  ```ruby
  def champ_value_for_tag(champ, path = :value)
    return champ.value if path == :value
    (champ.value_json&.dig("$.#{path}") || '').to_s
  end
  ```

**Specs** : supprimer les contextes `'with legacy data (fallback mode)'`

---

## Étape 4 : Supprimer le fallback legacy dans GraphQL

**Fichier** : `app/graphql/types/champs/referentiel_de_polynesie_champ_type.rb`

- Supprimer le bloc `# Fallback legacy` dans `columns`
- Ne garder que le mode upstream (`referentiel_mapping` + `value_json`)
  ```ruby
  field :columns, [Types::Champs::ReferentielChampType::ColumnType], null: false

  def columns
    return [] if object.data.blank?

    mapping = object.type_de_champ.referentiel_mapping_displayable_for_instructeur
    return [] if mapping.blank? || object.value_json.blank?

    mapping.map do |jsonpath, opts|
      {
        name: opts[:libelle] || jsonpath,
        value: format_value_for_api(object.value_json[jsonpath]),
        type: (opts[:type] || 'string').to_s
      }
    end
  end
  ```

---

## Étape 5 : Supprimer la vue legacy `_show.html.haml`

**Fichier** : `app/views/shared/champs/referentiel_de_polynesie/_show.html.haml`

Cette vue utilise encore `data['row']` et `data['{profile}_fields']`. Elle doit être remplacée par les composants upstream :
- `EditableChamp::ReferentielDisplayComponent` (côté usager)
- `ViewableChamp::ReferentielDisplayComponent` (côté instructeur)

Vérifier que tous les `render` pointent vers les composants et non vers cette vue partielle.

---

## Étape 6 : Supprimer le dual-write `sync_legacy_table_id`

**Fichier** : `app/controllers/administrateurs/referentiels_controller.rb`

- Supprimer la méthode `sync_legacy_table_id`
- Supprimer l'appel `sync_legacy_table_id(referentiel) if saved` dans `handle_referentiel_save`
- Supprimer le commentaire `# pf: dual-write pour rollback safe`

**Fichier** : `app/models/type_de_champ.rb`

- Simplifier `table_id` :
  ```ruby
  # Avant (dual-mode)
  def table_id
    referentiel&.try(:table_id)&.to_s.presence || options['table_id'].presence&.to_s || ''
  end

  # Après
  def table_id
    referentiel&.try(:table_id)&.to_s || ''
  end
  ```

**Specs** : supprimer les contextes `'quand options legacy table_id'`

---

## Étape 7 : Évaluer la suppression des clés Baserow config

Les clés `'Champs usager'` et `'Champs instructeur'` dans la config Baserow (`referentiel_de_polynesie.yml`) sont encore utilisées par :
- `BaserowReferentiel#headers` — pour construire la liste des colonnes disponibles
- La migration `populate_referentiel_mapping_from_baserow` — pour l'initialisation

**Question** : une fois que tous les TDC ont un `referentiel_mapping`, ces clés de config ne sont plus nécessaires au runtime. Elles ne servent plus qu'à la migration initiale.

**Action possible** : les conserver dans la config (sans coût) mais supprimer leur usage dans `BaserowReferentiel#headers` une fois que `headers` n'est plus appelé sans `referentiel_mapping`.

---

## Étape 8 : Nettoyage des specs

Supprimer tous les tests qui vérifient le comportement legacy :
- Contextes `'with legacy row format'`
- Contextes `'with legacy data (fallback mode)'`
- Contextes `'quand options legacy table_id'`
- Mocks de `fetch_instructeur_fields`

---

## Ordre d'exécution recommandé

```
Étape 0 (migration données)
  ↓
Étape 1 (normalized_data)  +  Étape 2 (fetch_external_data_legacy)
  ↓
Étape 3 (fetch_instructeur_fields)  +  Étape 4 (GraphQL)
  ↓
Étape 5 (vue _show.html.haml)
  ↓
Étape 6 (sync_legacy_table_id)
  ↓
Étape 7 (évaluation clés config)  +  Étape 8 (specs)
```

## Vérification

```bash
# Vérifier qu'aucune donnée legacy ne reste
bundle exec rails runner "
  legacy_row = Champ.joins(:type_de_champ).where(type_de_champ: { type_champ: 'referentiel_de_polynesie' }).where(\"data ? 'row'\").count
  no_mapping = TypeDeChamp.where(type_champ: 'referentiel_de_polynesie').where(\"referentiel_mapping IS NULL OR referentiel_mapping = '{}'\").count
  no_ref = TypeDeChamp.where(type_champ: 'referentiel_de_polynesie', referentiel_id: nil).count
  puts \"Legacy row data: #{legacy_row}, No mapping: #{no_mapping}, No referentiel: #{no_ref}\"
"

# Tests
bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb \
  spec/models/types_de_champ/referentiel_de_polynesie_type_de_champ_spec.rb \
  spec/models/referentiels/baserow_referentiel_spec.rb \
  spec/services/referentiels/baserow_service_spec.rb \
  spec/controllers/administrateurs/referentiels_controller_spec.rb \
  spec/models/concerns/dossier_export_referentiel_de_polynesie_spec.rb

# GraphQL
bin/rails graphql:schema:dump
```
