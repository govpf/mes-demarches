# Plan F — Source RDP (table + mode + indications) + découverte des tables/colonnes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Permettre à Claude de (1) **découvrir** les tables Baserow disponibles + lister les colonnes d'une table **avant** de créer le champ, et (2) **configurer les attributs de base** d'un champ `referentiel_de_polynesie` — `table_id` (obligatoire), `mode` de remplissage (autocomplete = avec complétion / exact_match = sans complétion), `hint` (indications usager) — traités comme des **options** du champ (cf. décision utilisateur : « rien de plus que les options d'un dropdown »).

**Architecture :** ces 3 attributs vivent sur le **`Referentiels::BaserowReferentiel`** lié au champ (pas dans le jsonb `options`). On étend `Mcp::ReferentielMappingService` avec : `tables_disponibles`, `colonnes_pour_table(table_id)` (découplé du champ), `configurer_source!(table_id:, mode:, hint:)` (build/update du BaserowReferentiel, purge du mapping si l'url change, dual-write legacy). Côté MCP, 2 nouveaux outils de découverte + `table_id`/`mode`/`hint` ajoutés au schéma `options` typé pour RDP (routés vers `configurer_source!` côté serveur).

**Tech Stack :** Rails 7 / graphql-ruby / RSpec (Baserow stubbé) ; TypeScript / zod / vitest.

**Pré-requis :** Plan C présent (`Mcp::ReferentielMappingService`, query `referentielChampConfig`, mutation `demarcheConfigurerReferentielMapping`, outils MCP référentiel). Branche `feature/mcp-construction-formulaires` / `main`.

---

## Mécanique vérifiée (à réutiliser)

- Découverte tables : `ReferentielDePolynesie::API.available_tables` → `[{ name:, id: }]` (référentiels actifs).
- Colonnes d'une table : `engine = ReferentielDePolynesie::API.engine` (la **classe** `BaserowAPI` ou nil) ; `engine.config(table_id)` ; `engine.fields(config)` → `{ id => { name:, type: } }` ; type via `ReferentielDePolynesie::BaserowAPI.baserow_type_to_mapping_type(field)`.
- Source : un champ RDP est lié à un `Referentiels::BaserowReferentiel` (`build_referentiel(type: Referentiels::BaserowReferentiel)`), qui porte `mode` (enum `exact_match`/`autocomplete`), `hint`, et `url`=`"baserow://<table_id>"` via accesseurs `table_id`/`table_id=`. `configured?` gate la sauvegarde.
- **Comportements à répliquer** (cf. `referentiels_controller#handle_referentiel_save`) : si `url_changed?` après save → **purger le mapping** `@tdc.update!(referentiel_mapping: {})` + reset `last_response`/`autocomplete_configuration` ; **dual-write legacy** `@tdc.update_column(:options, @tdc.options.merge('table_id' => referentiel.table_id.to_s))`.

---

## File Structure

**mes-demarches :**
- Modify: `app/services/mcp/referentiel_mapping_service.rb` (+ son spec) — `tables_disponibles`, `colonnes_pour_table`, `configurer_source!`, erreur `SourceInvalide`.
- Create: `app/graphql/resolvers/mcp/referentiels_de_polynesie.rb` (tables dispo), `app/graphql/resolvers/mcp/referentiel_colonnes.rb` (colonnes par table_id) + leurs types si besoin.
- Modify: `app/graphql/types/query_type.rb`.
- Modify: `app/graphql/mutations/demarche_ajouter_champ.rb` + `demarche_modifier_champ.rb` (router `table_id`/`mode`/`hint` vers `configurer_source!` pour un RDP) OU `app/graphql/mutations/demarche_champ_mutation.rb` (helper partagé `appliquer_source_referentiel!`).
- Modify: `app/graphql/types/mcp/referentiel_champ_config_type.rb` (exposer `mode` + `hint` courants).
- Specs : service + queries + mutation source.
- Modify (régénéré): schémas.

**mcp-mes-demarches :**
- Modify: `src/tools.ts` (+ test) : outils `lister_referentiels_de_polynesie`, `lister_colonnes_referentiel` ; ajouter `table_id`/`mode`/`hint` à `optionsSchema` (RDP). + `schema.graphql`.

---

## Task 1 : Étendre `Mcp::ReferentielMappingService` (tables, colonnes par table_id, source)

**Files:** Modify `app/services/mcp/referentiel_mapping_service.rb` + `spec/services/mcp/referentiel_mapping_service_spec.rb`.

- [ ] **Step 1 : Tests (écrire avant)** — ajouter au spec existant (réutiliser le stub `class_double(ReferentielDePolynesie::BaserowAPI)` sur `ReferentielDePolynesie::API.engine`, + stub `ReferentielDePolynesie::API.available_tables`) :
  - `#tables_disponibles` → délègue à `ReferentielDePolynesie::API.available_tables`.
  - `#colonnes_pour_table('24')` → `[{ nom:, type_mapping: }]` (et `#colonnes` délègue à `colonnes_pour_table(@tdc.table_id)`).
  - `#configurer_source!(table_id: '24', mode: 'autocomplete', hint: 'Saisissez…')` → crée/maj le `BaserowReferentiel` lié (mode/hint/table_id), `@tdc.referentiel.autocomplete?` vrai, `hint` posé, `table_id` (url) posé, et l'option legacy `options['table_id']` synchronisée.
  - changement de table_id avec un mapping existant → **mapping purgé** (`safe_referentiel_mapping` vide).
  - `mode` invalide → `SourceInvalide`.
  - Baserow indisponible (engine nil) sur `colonnes_pour_table` → `BaserowIndisponible`.

```ruby
  describe '#configurer_source!' do
    it 'crée le BaserowReferentiel (mode autocomplete + hint + table_id)' do
      service.configurer_source!(table_id: '24', mode: 'autocomplete', hint: 'Saisissez le nom de votre commune')
      ref = referentiel_tdc.reload.referentiel
      expect(ref).to be_a(Referentiels::BaserowReferentiel)
      expect(ref.autocomplete?).to be(true)
      expect(ref.hint).to eq('Saisissez le nom de votre commune')
      expect(ref.table_id).to eq('24')
      expect(referentiel_tdc.options['table_id']).to eq('24') # dual-write legacy
    end

    it 'purge le mapping quand la table change' do
      service.configurer_source!(table_id: '24', mode: 'exact_match')
      referentiel_tdc.update!(referentiel_mapping: { '$.X' => { 'type' => 'string', 'display_usager' => '1' } })
      described_class.new(referentiel_tdc.reload).configurer_source!(table_id: '99', mode: 'exact_match')
      expect(referentiel_tdc.reload.safe_referentiel_mapping).to be_empty
    end

    it 'refuse un mode invalide' do
      expect { service.configurer_source!(table_id: '24', mode: 'xxx') }
        .to raise_error(described_class::SourceInvalide, /mode/)
    end
  end
```

- [ ] **Step 2 : Lancer, vérifier l'échec.**

- [ ] **Step 3 : Implémenter** dans `app/services/mcp/referentiel_mapping_service.rb` :
```ruby
    class SourceInvalide < StandardError; end
    VALID_MODES = %w[autocomplete exact_match].freeze

    def tables_disponibles
      ReferentielDePolynesie::API.available_tables
    end

    def colonnes
      colonnes_pour_table(@tdc.table_id)
    end

    def colonnes_pour_table(table_id)
      fields = baserow_fields_for(table_id)
      fields.map { |_id, f| { nom: f[:name] || f['name'], type_mapping: ReferentielDePolynesie::BaserowAPI.baserow_type_to_mapping_type(f) } }
    end

    # pf: configure les attributs de base (source) du champ RDP. Ces attributs vivent sur
    # le BaserowReferentiel lié (pas dans options jsonb) ; on réplique le comportement de
    # l'éditeur : purge du mapping si l'url change + dual-write legacy options['table_id'].
    def configurer_source!(table_id: nil, mode: nil, hint: nil)
      if mode.present? && VALID_MODES.exclude?(mode.to_s)
        raise SourceInvalide, "mode invalide : « #{mode} » (attendu : #{VALID_MODES.join(' ou ')})."
      end

      referentiel = @tdc.referentiel
      referentiel = nil unless referentiel.is_a?(Referentiels::BaserowReferentiel)
      referentiel ||= @tdc.build_referentiel(type: Referentiels::BaserowReferentiel)

      referentiel.mode = mode if mode.present?
      referentiel.hint = hint unless hint.nil?
      referentiel.table_id = table_id.to_s if table_id.present?

      url_changed = referentiel.url_changed?
      raise SourceInvalide, "Configuration de la source incomplète (table_id requis)." unless referentiel.configured?

      referentiel.save!
      @tdc.update!(referentiel: referentiel) if @tdc.referentiel_id != referentiel.id
      @tdc.update!(referentiel_mapping: {}) if url_changed
      @tdc.update_column(:options, @tdc.options.merge('table_id' => referentiel.table_id.to_s))
      referentiel
    end

    private

    def baserow_fields_for(table_id)
      engine = ReferentielDePolynesie::API.engine
      raise BaserowIndisponible, 'Baserow n\'est pas configuré.' if engine.nil?

      config = engine.config(table_id)
      raise BaserowIndisponible, "Référentiel Baserow introuvable (table_id=#{table_id})." if config.nil?

      fields = engine.fields(config)
      raise BaserowIndisponible, 'Impossible de récupérer les colonnes du référentiel Baserow.' if fields.nil?

      fields
    end
```
(Refactorer l'ancien `baserow_fields` privé pour qu'il appelle `baserow_fields_for(@tdc.table_id)`, ou remplacer ses usages.)

- [ ] **Step 4 : Vert.** Si la persistance de `@tdc.referentiel_id` après `build_referentiel`+`save!` ne « prend » pas, ajuster (ex. `@tdc.update!(referentiel:)` après save, ou `referentiel.save!` puis `@tdc.update!(referentiel_id: referentiel.id)`) et reporter ce qui marche. Confirmer que `available_tables` est stubbé (pas de réseau).

- [ ] **Step 5 : Rubocop + commit**
```bash
bundle exec rubocop app/services/mcp/referentiel_mapping_service.rb
git add app/services/mcp/referentiel_mapping_service.rb spec/services/mcp/referentiel_mapping_service_spec.rb
git commit -m "feat(mcp): service — tables dispo, colonnes par table_id, config source RDP (table/mode/hint)"
```

---

## Task 2 : Queries de découverte + exposer mode/hint courants

**Files:** Create `app/graphql/resolvers/mcp/referentiels_de_polynesie.rb`, `app/graphql/resolvers/mcp/referentiel_colonnes.rb` (+ type `McpReferentielTable` si besoin) ; Modify `query_type.rb`, `referentiel_champ_config_type.rb` + resolver. Specs.

- [ ] **Step 1 : Tests** —
  - `referentielsDePolynesie` → liste `[{ id, nom }]` (stub `ReferentielDePolynesie::API.available_tables`). Pas besoin de démarche (config globale) — MAIS exiger un token authentifié (admin). Décision : exposer comme query top-level nécessitant `context.current_administrateur` présent (sinon erreur).
  - `referentielColonnes(tableId)` → `[{ nom, typeMapping }]` (stub engine), erreur si Baserow indispo. Auth : token admin présent.
  - `referentielChampConfig` retourne en plus `mode` (String, depuis `tdc.referentiel&.mode`) et `hint` (String, `tdc.referentiel&.hint`).

- [ ] **Step 2 : FAIL.**

- [ ] **Step 3 : Types + resolvers.**
  - `Types::Mcp::ReferentielTableType` (graphql_name 'McpReferentielTable') : `id: String!` (ou ID), `nom: String!`.
  - `Resolvers::Mcp::ReferentielsDePolynesie` : `type [Types::Mcp::ReferentielTableType], null: false` ; resolve → `ReferentielDePolynesie::API.available_tables.map { { id: _1[:id].to_s, nom: _1[:name] } }`. Auth : `raise GraphQL::ExecutionError unless context.current_administrateur` (lève déjà si token absent).
  - `Resolvers::Mcp::ReferentielColonnes` : args `table_id: String!` ; resolve → `Mcp::ReferentielMappingService.allocate`?? Non : extraire `colonnes_pour_table` en méthode utilisable sans tdc. **Décision** : ajouter une méthode de classe `Mcp::ReferentielMappingService.colonnes_pour_table(table_id)` (sans instance) OU un petit service `Mcp::ReferentielColonnesService`. Le resolver l'appelle, rescue `BaserowIndisponible` → ExecutionError. Auth admin présent.
  - `referentiel_champ_config_type.rb` : ajouter `field :mode, String, null: true` + `field :hint, String, null: true` ; le resolver `referentiel_champ_config.rb` ajoute `mode: tdc.referentiel&.mode, hint: tdc.referentiel&.hint` au hash.

> Décision d'implémentation : pour `colonnes_pour_table` réutilisable hors instance, le plus simple est une **méthode de classe** sur le service (`def self.colonnes_pour_table(table_id)`) que l'instance `#colonnes` et le resolver appellent tous deux. Adapter Task 1 en conséquence si plus propre.

- [ ] **Step 4 : Enregistrer** dans `query_type.rb` (sous `# pf:`) : `referentiels_de_polynesie` (resolver) + `referentiel_colonnes` (resolver).

- [ ] **Step 5 : Vert + rubocop + commit** — « feat(graphql): queries referentielsDePolynesie + referentielColonnes + mode/hint dans referentielChampConfig ».

---

## Task 3 : Router table_id/mode/hint comme options RDP (ajouter/modifier)

**But :** côté UX, ces attributs sont des « options ». Côté serveur, pour un `referentiel_de_polynesie`, on les **extrait** des options et on les route vers `configurer_source!` (le reste — `drop_down_other` — passe par le chemin générique). `referentiel_mapping` n'est pas géré ici (il l'est par `demarcheConfigurerReferentielMapping`).

**Files:** Modify `app/graphql/mutations/demarche_champ_mutation.rb` (helper `appliquer_source_referentiel!`) + `demarche_ajouter_champ.rb` + `demarche_modifier_champ.rb`. Spec dans `spec/graphql/mutations/demarche_champ_mutations_spec.rb`.

- [ ] **Step 1 : Tests** — `ajouter_champ typeChamp: 'referentiel_de_polynesie', options: { table_id: '24', mode: 'autocomplete', hint: 'Saisissez…' }` → champ créé, `referentiel.autocomplete?`, `hint` et `table_id` posés. `modifier_champ` idem. `mode` invalide → `errors`.

- [ ] **Step 2 : FAIL.**

- [ ] **Step 3 : Implémenter** dans `demarche_champ_mutation.rb` (private) :
```ruby
    REFERENTIEL_SOURCE_KEYS = %w[table_id mode hint].freeze

    # pf: pour un champ RDP, extrait table_id/mode/hint des options et configure la source
    # (BaserowReferentiel) via le service. Retourne [options_restantes, erreur|nil].
    def extraire_et_appliquer_source_referentiel!(type_de_champ, options)
      return [options, nil] unless type_de_champ.type_champ == 'referentiel_de_polynesie'
      return [options, nil] if options.blank?

      source = options.slice(*REFERENTIEL_SOURCE_KEYS, *REFERENTIEL_SOURCE_KEYS.map(&:to_sym))
      return [options, nil] if source.empty?

      ::Mcp::ReferentielMappingService.new(type_de_champ).configurer_source!(
        table_id: source['table_id'] || source[:table_id],
        mode: source['mode'] || source[:mode],
        hint: source['hint'] || source[:hint]
      )
      [options.except(*REFERENTIEL_SOURCE_KEYS, *REFERENTIEL_SOURCE_KEYS.map(&:to_sym)), nil]
    rescue ::Mcp::ReferentielMappingService::SourceInvalide, ::Mcp::ReferentielMappingService::BaserowIndisponible => e
      [options, e.message]
    end
```
Dans `ajouter_champ` (après création du tdc + valid?) et `modifier_champ` (après `find_and_ensure_exclusive_use`), AVANT `appliquer_options!` :
```ruby
      remaining_options, source_error = extraire_et_appliquer_source_referentiel!(type_de_champ, options)
      return { errors: [source_error] } if source_error
      options = remaining_options
```
puis continuer avec `appliquer_options!(type_de_champ, options)` pour les options restantes (drop_down_other…). ⚠️ Comme `mode`/`hint` ne sont PAS dans `OPTS_BY_TYPE`, il est crucial de les **retirer** des options avant `appliquer_options!` (sinon « options non autorisées »).

- [ ] **Step 4 : Vert + rubocop + commit** — « feat(graphql): options source RDP (table_id/mode/hint) routées vers configurer_source! ».

---

## Task 4 : Dump schéma + copie

- [ ] Vérifier toutes les specs nouvelles vertes ; `bin/rails graphql:schema:dump` ; `grep -E "referentielsDePolynesie|referentielColonnes|McpReferentielTable" app/graphql/schema.graphql` ; SDL additif (0 suppression) ; `cp ... ../mcp-mes-demarches/schema.graphql` ; commit schémas.

---

## Task 5 : Outils MCP (découverte + options source)

**Files:** Modify `src/tools.ts`, `src/tools.test.ts`, `schema.graphql`.

- [ ] **Step 1 : Tests** — la liste passe à **11 outils** ; `lister_referentiels_de_polynesie` (sans arg, query `referentielsDePolynesie`) → JSON ; `lister_colonnes_referentiel(tableId)` (query `referentielColonnes`) → JSON.

- [ ] **Step 2 : FAIL.**

- [ ] **Step 3 : Implémenter** —
  - Ajouter à `optionsSchema` (typé) : `table_id` (string, « id Baserow ; cf. lister_referentiels_de_polynesie ; obligatoire pour un référentiel »), `mode` (`z.enum(['autocomplete','exact_match'])`, « avec/sans complétion »), `hint` (string, « indications de saisie pour l'usager (obligatoire) »). `.passthrough()` reste.
  - 2 outils :
```ts
  {
    name: 'lister_referentiels_de_polynesie',
    description: "Liste les référentiels Baserow disponibles (id + nom) à utiliser comme table_id d'un champ referentiel_de_polynesie.",
    inputSchema: {},
    run: async ({ gql }) => {
      const data = await gql(`query { referentielsDePolynesie { id nom } }`, {});
      return { content: [{ type: 'text', text: JSON.stringify(data.referentielsDePolynesie, null, 2) }] };
    }
  },
  {
    name: 'lister_colonnes_referentiel',
    description: "Liste les colonnes (nom + type) d'une table de référentiel Baserow à partir de son tableId, AVANT de créer le champ — pour préparer le mapping. Erreur si Baserow injoignable.",
    inputSchema: { tableId: z.string().describe('id de la table Baserow (cf. lister_referentiels_de_polynesie).') },
    run: async ({ gql }, { tableId }) => {
      const data = await gql(`query($tableId: String!){ referentielColonnes(tableId: $tableId){ nom typeMapping } }`, { tableId });
      return { content: [{ type: 'text', text: JSON.stringify(data.referentielColonnes, null, 2) }] };
    }
  }
```
  - Enrichir la description de `ajouter_champ`/`modifier_champ` : pour `referentiel_de_polynesie`, fournir `options.table_id` (obligatoire) + `mode` + `hint`.

- [ ] **Step 4 : Vert + typecheck + build + commit** — « feat: outils MCP lister_referentiels_de_polynesie + lister_colonnes_referentiel + options source RDP ».

---

## Self-Review (à l'écriture)

- **Couverture :** découverte tables (Task 2/5), colonnes par table_id découplé (Task 1/2/5, résout l'œuf-et-poule de Q2), config source table/mode/hint comme options (Task 1/3/5, Q1), exposition mode/hint en lecture (Task 2).
- **Workflow Q2 visé :** `lister_referentiels_de_polynesie` → `lister_colonnes_referentiel(tableId)` → `ajouter_champ(referentiel_de_polynesie, options:{table_id, mode, hint, …display via referentiel_mapping ultérieur})`. Le **prefill** reste un `configurer_referentiel_mapping` ultérieur (cibles créées après).
- **Couplage / friction :** réutilise `available_tables`, `engine`, `build_referentiel`, `baserow_type_to_mapping_type` (publics). Comportements éditeur répliqués (purge mapping si url change, dual-write). Pas de refactor upstream hors enregistrements `# pf:`.
- **Risques signalés :** persistance `referentiel_id` après `build_referentiel`+save (à confirmer au test) ; `mode`/`hint` doivent être retirés des options avant `appliquer_options!` (sinon rejet OPTS_BY_TYPE) ; `referentielColonnes`/`referentielsDePolynesie` exigent un token admin (pas de scope démarche — config globale Baserow).

## Hors périmètre

Référentiels API génériques (auth/URL/test) ; basculer public↔privé d'un champ existant ; agrégats/colonnes imbriquées.
