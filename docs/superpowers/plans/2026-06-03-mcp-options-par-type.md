# Plan E — Options par type de champ (drop-down, min/max, …) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre à Claude de configurer les **options spécifiques par type** d'un champ (valeurs d'une liste déroulante, bornes min/max d'un nombre, limite de caractères, etc.) via les outils MCP, en écriture par un blob JSON validé contre les clés autorisées du type.

**Architecture :** Côté `mes-demarches`, un scalaire GraphQL `Types::Json` + un helper partagé `appliquer_options!` dans la base `Mutations::DemarcheChampMutation` qui (a) **réutilise** la map canonique `TypeDeChamp::OPTS_BY_TYPE` (qui fusionne déjà options standard + PF) pour rejeter les clés non autorisées, (b) normalise les valeurs (booléen→`"1"`/`"0"`, nombre→string, tableaux tels quels), (c) applique via le setter existant `type_de_champ.editable_options=` (merge dans `options`). L'argument `options: Json` est ajouté à `demarcheAjouterChamp` et `demarcheModifierChamp`. Côté `mcp-mes-demarches`, les outils `ajouter_champ`/`modifier_champ` gagnent un champ `options` **typé** (objet Zod : `drop_down_options: string[]`, `positive_number: boolean`, `max_number: number`, …, `.passthrough()` pour les options PF avancées). Le SDK MCP expose ce schéma typé à Claude → **Claude connaît la forme attendue de chaque option** (c'est la réponse à la découvrabilité : guidage par le schéma de l'outil, pas par un blob libre). Le serveur reste seul juge des clés valides par type.

**Tech Stack :** Rails 7 / graphql-ruby / RSpec ; TypeScript / zod / vitest.

**Pré-requis :** Plans A/B/D présents. Branche `feature/mcp-construction-formulaires` (mes-demarches) ; branche `main` (mcp-mes-demarches).

**Réutilisations vérifiées (pas de refactor) :**
- `TypeDeChamp::OPTS_BY_TYPE` (l.815-835) — `{ "drop_down_list" => [:drop_down_other, :drop_down_options, :drop_down_mode], "integer_number" => [:positive_number, :min_number, :max_number, :range_number], "textarea" => [:character_limit], … }`, fusionne déjà `INSTANCE_OPTIONS_BY_TYPE` (PF). Clés = strings ; valeurs = symboles.
- `type_de_champ.editable_options=(options)` (l.695) → `self.options.merge!(options)` (setter de l'éditeur).
- Flags booléens stockés en `"1"`/`"0"` (`positive_number? == "1"`). `drop_down_options` = tableau de strings.
- `Types::BaseScalar` existe (cf. `Types::GeoJSON::CoordinatesType`).

---

## File Structure

**Repo `mes-demarches` (Task 1) :**
- Create: `app/graphql/types/json.rb` — scalaire `Types::Json`.
- Modify: `app/graphql/mutations/demarche_champ_mutation.rb` — helper `appliquer_options!`.
- Modify: `app/graphql/mutations/demarche_ajouter_champ.rb` — argument `options`.
- Modify: `app/graphql/mutations/demarche_modifier_champ.rb` — argument `options`.
- Modify: `spec/graphql/mutations/demarche_champ_mutations_spec.rb`.
- Modify (régénéré): `app/graphql/schema.graphql`, `app/graphql/schema.json`.

**Repo `mcp-mes-demarches` (Task 2) :**
- Modify: `src/tools.ts`, `src/tools.test.ts`, `schema.graphql` (copie).

---

## Task 1 : Scalaire JSON + helper + options sur les 2 mutations (mes-demarches)

**Files:**
- Create: `app/graphql/types/json.rb`
- Modify: `app/graphql/mutations/demarche_champ_mutation.rb`
- Modify: `app/graphql/mutations/demarche_ajouter_champ.rb`
- Modify: `app/graphql/mutations/demarche_modifier_champ.rb`
- Test: `spec/graphql/mutations/demarche_champ_mutations_spec.rb`

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter dans le `RSpec.describe 'Mutations MCP construction de champs'`, dans le `describe 'demarcheAjouterChamp'`, une nouvelle context, ET dans `describe 'demarcheModifierChamp'` deux nouvelles contexts :

```ruby
  # --- à l'intérieur de describe 'demarcheAjouterChamp' ---
    context 'avec options (liste déroulante)' do
      let(:query) do
        <<-GRAPHQL
        mutation($input: DemarcheAjouterChampInput!) {
          demarcheAjouterChamp(input: $input) { champStableId errors { message } }
        }
        GRAPHQL
      end
      let(:variables) do
        { input: { demarche: { number: procedure.id }, typeChamp: 'drop_down_list', libelle: 'Civilité',
                   options: { drop_down_options: ['M.', 'Mme'], drop_down_other: true } } }
      end

      it 'crée le champ avec ses options' do
        expect(data[:demarcheAjouterChamp][:errors]).to be_nil
        tdc = procedure.draft_revision.reload.types_de_champ.find { _1.libelle == 'Civilité' }
        expect(tdc.drop_down_options).to include('M.', 'Mme')
        expect(tdc.drop_down_other).to eq('1') # booléen normalisé
      end
    end

  # --- à l'intérieur de describe 'demarcheModifierChamp' ---
    context 'avec options valides (bornes numériques)' do
      let(:procedure) { create(:procedure, administrateurs: [admin], types_de_champ_public: [{ type: :integer_number, libelle: 'Âge' }]) }
      let(:query) do
        <<-GRAPHQL
        mutation($input: DemarcheModifierChampInput!) {
          demarcheModifierChamp(input: $input) { champStableId errors { message } }
        }
        GRAPHQL
      end
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s,
                   options: { positive_number: true, min_number: '0', max_number: '120' } } }
      end

      it 'applique les options' do
        expect(data[:demarcheModifierChamp][:errors]).to be_nil
        tdc = procedure.draft_revision.reload.types_de_champ.first
        expect(tdc.positive_number?).to eq(true)
        expect(tdc.min_number).to eq('0')
        expect(tdc.max_number).to eq('120')
      end
    end

    context 'avec une option non autorisée pour le type' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s,
                   options: { min_number: '0' } } } # texte n'autorise pas min_number
      end

      it 'est refusé avec la liste des options valides' do
        expect(data[:demarcheModifierChamp][:champStableId]).to be_nil
        expect(data[:demarcheModifierChamp][:errors].first[:message]).to include('non autorisées')
      end
    end
```

(Le `stable_id` du describe modifier pointe sur le 1er champ du `procedure` par défaut, un `text` — d'où le refus de `min_number`. La context « bornes numériques » redéfinit `procedure` avec un `integer_number`.)

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e "options"`
Expected: FAIL (`options` argument inconnu / `DemarcheAjouterChampInput` n'a pas de champ `options`).

- [ ] **Step 3 : Créer le scalaire `Types::Json`**

Créer `app/graphql/types/json.rb` :

```ruby
# frozen_string_literal: true

# pf: scalaire JSON générique pour transmettre un objet d'options arbitraire (validé
# côté serveur contre les clés autorisées du type de champ). Utilisé par le MCP.
module Types
  class Json < Types::BaseScalar
    description "Objet JSON arbitraire (clé/valeur)."

    def self.coerce_input(value, _context)
      value
    end

    def self.coerce_result(value, _context)
      value
    end
  end
end
```

- [ ] **Step 4 : Ajouter le helper dans la base**

Dans `app/graphql/mutations/demarche_champ_mutation.rb`, ajouter dans la section `private` :

```ruby
    # pf: valide + normalise + applique un blob d'options sur un type de champ.
    # Réutilise TypeDeChamp::OPTS_BY_TYPE (map canonique, options standard + PF) pour
    # rejeter toute clé non autorisée. Retourne nil si OK, ou un message d'erreur.
    # N'applique que sur le tdc (en mémoire) ; l'appelant doit sauvegarder.
    def appliquer_options!(type_de_champ, options)
      return nil if options.blank?

      allowed = TypeDeChamp::OPTS_BY_TYPE.fetch(type_de_champ.type_champ) { [] }.map(&:to_s)
      unknown = options.keys.map(&:to_s) - allowed
      if unknown.any?
        return "Options non autorisées pour le type « #{type_de_champ.type_champ} » : #{unknown.join(', ')}." \
               " Options valides : #{allowed.empty? ? '(aucune)' : allowed.join(', ')}."
      end

      normalized = options.to_h.to_h do |key, value|
        normalized_value = case value
        when true then '1'
        when false then '0'
        when Numeric then value.to_s
        else value
        end
        [key.to_s, normalized_value]
      end

      type_de_champ.editable_options = normalized
      nil
    end
```

- [ ] **Step 5 : Ajouter `options` à `demarcheAjouterChamp`**

Dans `app/graphql/mutations/demarche_ajouter_champ.rb` :
- ajouter l'argument : `argument :options, Types::Json, "Options spécifiques au type (ex. { drop_down_options: [...] }).", required: false`
- dans `resolve`, après que `type_de_champ` est créé et valide, appliquer les options puis sauvegarder. Remplacer le bloc final :

```ruby
      type_de_champ = procedure.draft_revision.add_type_de_champ(params)

      return { errors: type_de_champ.errors.full_messages } unless type_de_champ.valid?

      if options.present?
        error = appliquer_options!(type_de_champ, options)
        return { errors: [error] } if error
        type_de_champ.save!
      end

      { champ_stable_id: type_de_champ.stable_id.to_s }
```
(et ajouter `options: nil` aux paramètres de `resolve`, c.-à-d. `def resolve(demarche:, type_champ:, libelle:, description: nil, obligatoire: false, prive: false, parent_stable_id: nil, apres_stable_id: nil, options: nil)`.)

- [ ] **Step 6 : Ajouter `options` à `demarcheModifierChamp`**

Dans `app/graphql/mutations/demarche_modifier_champ.rb` :
- ajouter l'argument : `argument :options, Types::Json, "Options spécifiques au type (ex. { positive_number: true, max_number: '100' }).", required: false`
- ajouter `options: nil` à la signature de `resolve`.
- la garde « aucune modification fournie » doit tenir compte de `options` : remplacer
  `return { errors: ["Aucune modification fournie."] } if attrs.empty?`
  par
  `return { errors: ["Aucune modification fournie."] } if attrs.empty? && options.blank?`
- après `type_de_champ = draft.find_and_ensure_exclusive_use(stable_id)`, appliquer les options AVANT le `update`/`save`. Restructurer la fin :

```ruby
      type_de_champ = draft.find_and_ensure_exclusive_use(stable_id)

      if options.present?
        error = appliquer_options!(type_de_champ, options)
        return { errors: [error] } if error
      end

      type_de_champ.assign_attributes(attrs)

      if type_de_champ.save
        { champ_stable_id: stable_id.to_s }
      else
        { errors: type_de_champ.errors.full_messages }
      end
```
(`assign_attributes` + `save` remplace `update(attrs)` pour combiner attrs + options en une sauvegarde. Si `attrs` est vide mais `options` présent, `save` persiste quand même le merge d'options effectué par `editable_options=`.)

- [ ] **Step 7 : Lancer, vérifier que ça passe**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb`
Expected: tous verts (anciens + nouveaux). Si `drop_down_options` ne contient pas les valeurs, vérifier le getter `drop_down_options` (non-advanced → `Array.wrap(super)`), et que `editable_options=` a bien mergé la clé `"drop_down_options"`.

- [ ] **Step 8 : Rubocop + dump schéma + copie + commit**

```bash
bundle exec rubocop app/graphql/types/json.rb app/graphql/mutations/demarche_champ_mutation.rb app/graphql/mutations/demarche_ajouter_champ.rb app/graphql/mutations/demarche_modifier_champ.rb
bin/rails graphql:schema:dump
grep -E "options: JSON|scalar JSON|JSON" app/graphql/schema.graphql | head
cp app/graphql/schema.graphql /home/clautier/Rubymine/mcp-mes-demarches/schema.graphql
git add app/graphql/types/json.rb app/graphql/mutations/demarche_champ_mutation.rb app/graphql/mutations/demarche_ajouter_champ.rb app/graphql/mutations/demarche_modifier_champ.rb spec/graphql/mutations/demarche_champ_mutations_spec.rb app/graphql/schema.graphql app/graphql/schema.json
git commit -m "feat(graphql): options par type (scalaire Json + appliquer_options!) sur ajouter/modifier champ"
```

---

## Task 2 : Exposer `options` dans les outils MCP (mcp-mes-demarches)

**Files (dans `/home/clautier/Rubymine/mcp-mes-demarches`, branche `main`) :**
- Modify: `src/tools.ts`, `src/tools.test.ts`

- [ ] **Step 1 : Ajouter les tests qui échouent (`src/tools.test.ts`)**

Ajouter :

```ts
  it('ajouter_champ transmet les options', async () => {
    const gql = vi.fn().mockResolvedValue({ demarcheAjouterChamp: { champStableId: '50', errors: null } });
    await byName('ajouter_champ').run({ gql }, {
      demarcheNumber: 7, typeChamp: 'drop_down_list', libelle: 'Civilité',
      options: { drop_down_options: ['M.', 'Mme'], drop_down_other: true }
    });
    const [, variables] = gql.mock.calls[0];
    expect(variables.input.options).toEqual({ drop_down_options: ['M.', 'Mme'], drop_down_other: true });
  });

  it('modifier_champ transmet les options', async () => {
    const gql = vi.fn().mockResolvedValue({ demarcheModifierChamp: { champStableId: '9', errors: null } });
    await byName('modifier_champ').run({ gql }, { demarcheNumber: 1, stableId: '9', options: { max_number: 100 } });
    const [, variables] = gql.mock.calls[0];
    expect(variables.input.options).toEqual({ max_number: 100 });
  });
```

- [ ] **Step 2 : Lancer, vérifier l'échec** : `npm test` → FAIL (options non transmis).

- [ ] **Step 3 : Modifier `src/tools.ts`**

**Clé de découvrabilité (répond à « comment Claude connaît la forme d'une option ») :** `options` est un **objet Zod typé** (pas un `record` libre). Le SDK MCP expose ce schéma à Claude en JSON Schema → Claude voit le type + la description de chaque option. `.passthrough()` laisse passer les options PF avancées (visa, formule, te_fenua…) sans les typer une par une.

Définir en haut de `src/tools.ts` un schéma partagé :

```ts
// pf: options par type, typées pour guider Claude (le SDK MCP expose ces types en JSON Schema).
// Le serveur valide les clés par type (OPTS_BY_TYPE) ; .passthrough() autorise les options
// PF avancées (visa: accredited_users, formule: formule_expression, te_fenua…) non typées ici.
const optionsSchema = z.object({
  // Listes déroulantes (drop_down_list, multiple_drop_down_list, linked_drop_down_list)
  drop_down_options: z.array(z.string()).optional().describe('Valeurs de la liste déroulante.'),
  drop_down_other: z.boolean().optional().describe('Autoriser une réponse libre « Autre ».'),
  // Nombres (integer_number, decimal_number)
  positive_number: z.boolean().optional().describe('Forcer un nombre positif.'),
  min_number: z.number().optional().describe('Borne minimale.'),
  max_number: z.number().optional().describe('Borne maximale.'),
  // Texte long (textarea)
  character_limit: z.number().optional().describe('Limite de caractères.'),
  // Date (date, datetime)
  date_in_past: z.boolean().optional().describe('N\'autoriser que des dates passées.')
}).passthrough().describe("Options spécifiques au type de champ. Seules les options valides pour le type choisi sont acceptées (sinon erreur).");
```

- Dans le tool `ajouter_champ` : ajouter `options: optionsSchema.optional()` à `inputSchema`, et inclure `options` dans la boucle des clés copiées : `for (const k of ['description', 'obligatoire', 'prive', 'parentStableId', 'apresStableId', 'options'] as const)`.
- Dans le tool `modifier_champ` : ajouter `options: optionsSchema.optional()` à `inputSchema`, et ajouter `'options'` à la boucle : `for (const k of ['libelle', 'description', 'obligatoire', 'typeChamp', 'options'] as const)`.
- Enrichir la `description` des 2 outils : mentionner que les options dépendent du type (listes → `drop_down_options`/`drop_down_other` ; nombres → `positive_number`/`min_number`/`max_number` ; texte long → `character_limit`), et que `lire_demarche` + un message d'erreur listent les options valides en cas de doute.

- [ ] **Step 4 : Lancer, vérifier que ça passe** : `npm test` → tous verts (anciens + 2 nouveaux).

- [ ] **Step 5 : Typecheck + build + commit**

```bash
cd /home/clautier/Rubymine/mcp-mes-demarches
npm run typecheck && npm test && npm run build
git add src/tools.ts src/tools.test.ts schema.graphql
git commit -m "feat: option \`options\` (config par type) sur ajouter_champ et modifier_champ"
```

---

## Self-Review (effectuée à l'écriture)

- **Couverture :** Task 1 = scalaire + helper réutilisant `OPTS_BY_TYPE` + `options` sur les 2 mutations, testé (drop-down à la création, bornes numériques, rejet de clé non autorisée, normalisation booléenne). Task 2 = transmission des options par les 2 outils MCP, testé. Le périmètre « options par type » est couvert pour le MVP (drop-down, nombres, texte ; les options PF — visa accredited_users, formule, te_fenua — passent par le même mécanisme générique, sans code dédié).
- **Placeholders :** aucun. Un point à VÉRIFIER au Step 7 : que `editable_options=` persiste bien `drop_down_options` lisible par le getter (sinon utiliser `drop_down_options_from_text=` pour ce cas).
- **Cohérence :** `appliquer_options!` vit dans la base partagée et est appelé identiquement par les 2 mutations ; retour `{ champ_stable_id }`/`{ errors }` inchangé ; `Types::Json` est un scalaire passthrough validé côté serveur (pas de confiance au client).

## Risque résiduel

- `drop_down_options` : le getter a un chemin « advanced » (référentiel). Pour une liste simple, `editable_options = { 'drop_down_options' => [...] }` puis `save` doit suffire ; à confirmer par le test. Si la persistance ne « prend » pas, fallback : `type_de_champ.drop_down_options_from_text = valeurs.join("\n")`.
- Validation de la *forme* des valeurs (ex. `drop_down_options` doit être un tableau) non couverte : on valide les clés, pas les types de valeurs. Une valeur malformée serait rejetée par les validations modèle au `save` (remontée comme `errors`). Acceptable pour le MVP.
