# Plan D — Serveur MCP TypeScript (MVP utilisable par Claude) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Livrer un MVP où un administrateur, dans Claude (Desktop/Code), construit la structure d'une démarche en langage naturel : un serveur MCP local (stdio, TypeScript) expose des outils qui appellent l'API GraphQL de mes-demarches (mutations des Plans A & B + une query de lecture).

**Architecture :** Deux repos. (1) `mes-demarches` gagne **une** query PF de lecture `demarcheChamps` exposant les `stable_id` (la query `demarche` standard ne donne qu'un id global, inutilisable par les mutations qui attendent un `stable_id`). (2) `../mcp-mes-demarches` (TypeScript, repo séparé déjà cloné) contient le serveur MCP : un client GraphQL authentifié par token Bearer, et 6 outils data-driven (`lire_demarche` + `ajouter/modifier/deplacer/supprimer_champ` + `definir_condition`) qui traduisent un appel d'outil en opération GraphQL.

**Tech Stack :** Rails 7 / graphql-ruby / RSpec (repo 1) ; Node ≥18, TypeScript, `@modelcontextprotocol/sdk`, `zod`, `vitest` (repo 2).

**Pré-requis :** Plans A & B présents sur `feature/mcp-construction-formulaires` (5 mutations + schéma dumpé). Repo `../mcp-mes-demarches` cloné (remote `github.com/maatinito/mcp-mes-demarches`).

**Hypothèses d'auth (vérifiées) :** endpoint `POST /api/v2/graphql` ; en-tête `Authorization: Bearer <APIToken>` (via `authenticate_with_http_token`). Le token doit être `write_access` + scopé à la procédure + (en prod) restreint au réseau de l'admin. En Phase A (local), l'admin crée le token dans son profil mes-demarches.

---

## File Structure

**Repo `mes-demarches` (Task 1) :**
- Create: `app/graphql/types/mcp/champ_structure_type.rb` — type de sortie `Types::Mcp::ChampStructureType` (PF, isolé).
- Create: `app/graphql/resolvers/mcp/demarche_champs.rb` — resolver `Resolvers::Mcp::DemarcheChamps`.
- Modify: `app/graphql/types/query_type.rb` — enregistrer la query (ligne `# pf:`).
- Create: `spec/graphql/queries/demarche_champs_spec.rb`.
- Modify (régénéré): `app/graphql/schema.graphql`, `app/graphql/schema.json`.

**Repo `../mcp-mes-demarches` (Tasks 2-5) :**
- Create: `package.json`, `tsconfig.json`, `vitest.config.ts`, `.gitignore`, `.env.example`, `README.md`.
- Create: `src/config.ts`, `src/graphql.ts`, `src/tools.ts`, `src/server.ts`, `src/index.ts`.
- Create: `src/graphql.test.ts`, `src/tools.test.ts`.

---

## Task 1 : Query PF de lecture `demarcheChamps` (repo mes-demarches)

**But :** exposer la structure du brouillon avec les `stable_id` (que les mutations attendent).

**Files:**
- Create: `app/graphql/types/mcp/champ_structure_type.rb`
- Create: `app/graphql/resolvers/mcp/demarche_champs.rb`
- Modify: `app/graphql/types/query_type.rb`
- Test: `spec/graphql/queries/demarche_champs_spec.rb`

- [ ] **Step 1 : Écrire le test qui échoue**

Créer `spec/graphql/queries/demarche_champs_spec.rb` :

```ruby
# frozen_string_literal: true

RSpec.describe 'Query demarcheChamps', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:procedure) do
    create(:procedure, administrateurs: [admin], types_de_champ_public: [
      { type: :text, libelle: 'Nom' },
      { type: :integer_number, libelle: 'Âge' },
    ])
  end
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }
  let(:query) do
    <<-GRAPHQL
    query($demarche: FindDemarcheInput!) {
      demarcheChamps(demarche: $demarche) {
        stableId
        typeChamp
        libelle
        obligatoire
        prive
        parentStableId
        aCondition
      }
    }
    GRAPHQL
  end
  let(:variables) { { demarche: { number: procedure.id } } }

  subject { API::V2::Schema.execute(query, variables:, context:) }
  let(:data) { subject['data'].deep_symbolize_keys }

  it 'retourne les champs du brouillon avec leur stable_id' do
    champs = data[:demarcheChamps]
    expect(champs.map { _1[:libelle] }).to eq(['Nom', 'Âge'])
    expect(champs.map { _1[:typeChamp] }).to eq(['text', 'integer_number'])
    expect(champs.first[:stableId]).to eq(procedure.draft_revision.types_de_champ.first.stable_id.to_s)
    expect(champs.first[:aCondition]).to eq(false)
  end

  context 'démarche non autorisée pour le token' do
    let(:other) { create(:procedure) }
    let(:variables) { { demarche: { number: other.id } } }

    it 'remonte une erreur' do
      expect(subject['errors']).to be_present
    end
  end
end
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run: `bundle exec rspec spec/graphql/queries/demarche_champs_spec.rb`
Expected: FAIL (champ `demarcheChamps` inexistant).

- [ ] **Step 3 : Créer le type de sortie**

Créer `app/graphql/types/mcp/champ_structure_type.rb` :

```ruby
# frozen_string_literal: true

# pf: structure simplifiée d'un champ, exposée au serveur MCP (avec le stable_id que les
# mutations de construction attendent — l'id global de ChampDescriptor ne convient pas).
module Types
  module Mcp
    class ChampStructureType < Types::BaseObject
      graphql_name 'McpChampStructure'

      field :stable_id, String, null: false
      field :type_champ, String, null: false
      field :libelle, String, null: false
      field :description, String, null: true
      field :obligatoire, Boolean, null: false
      field :prive, Boolean, null: false
      field :parent_stable_id, String, null: true
      field :position, Integer, null: false
      field :a_condition, Boolean, null: false
    end
  end
end
```

- [ ] **Step 4 : Créer le resolver**

Créer `app/graphql/resolvers/mcp/demarche_champs.rb` :

```ruby
# frozen_string_literal: true

# pf: liste les champs (publics + privés) de la révision brouillon d'une démarche, avec
# leur stable_id, pour le serveur MCP. Lecture seule ; autorisation par scope du token.
module Resolvers
  module Mcp
    class DemarcheChamps < GraphQL::Schema::Resolver
      type [Types::Mcp::ChampStructureType], null: false

      argument :demarche, Types::DemarcheDescriptorType::FindDemarcheInput, "La démarche cible.", required: true

      def resolve(demarche:)
        number = demarche.number.presence || ApplicationRecord.id_from_typed_id(demarche.id)
        procedure = Procedure.find_by(id: number)
        raise GraphQL::ExecutionError, "La démarche \"#{number}\" n'existe pas." if procedure.nil?
        raise GraphQL::ExecutionError, "Vous n'avez pas accès à la démarche \"#{number}\"." unless context.authorized_demarche?(procedure)

        procedure.draft_revision.revision_types_de_champ.map do |coordinate|
          tdc = coordinate.type_de_champ
          {
            stable_id: tdc.stable_id.to_s,
            type_champ: tdc.type_champ,
            libelle: tdc.libelle,
            description: tdc.description,
            obligatoire: tdc.mandatory?,
            prive: coordinate.private?,
            parent_stable_id: coordinate.parent&.stable_id&.to_s,
            position: coordinate.position,
            a_condition: tdc.condition.present?
          }
        end
      end
    end
  end
end
```

- [ ] **Step 5 : Enregistrer la query**

Dans `app/graphql/types/query_type.rb`, ajouter dans le corps de la classe (avec les autres `field`), précédé d'un commentaire `# pf:` :

```ruby
    # pf: lecture de la structure d'une démarche pour le serveur MCP (expose les stable_id)
    field :demarche_champs, resolver: Resolvers::Mcp::DemarcheChamps, description: "Champs de la révision brouillon d'une démarche (pour le MCP)."
```

- [ ] **Step 6 : Lancer, vérifier que ça passe**

Run: `bundle exec rspec spec/graphql/queries/demarche_champs_spec.rb`
Expected: PASS (2 exemples). Si le test « non autorisée » ne lève pas d'erreur, vérifier que `context.authorized_demarche?` est bien appelé.

- [ ] **Step 7 : Rubocop + dump schéma + commit**

```bash
bundle exec rubocop app/graphql/types/mcp/champ_structure_type.rb app/graphql/resolvers/mcp/demarche_champs.rb
bin/rails graphql:schema:dump
grep -E "demarcheChamps|McpChampStructure" app/graphql/schema.graphql   # doit apparaître
git add app/graphql/types/mcp/champ_structure_type.rb app/graphql/resolvers/mcp/demarche_champs.rb app/graphql/types/query_type.rb spec/graphql/queries/demarche_champs_spec.rb app/graphql/schema.graphql app/graphql/schema.json
git commit -m "feat(graphql): query demarcheChamps (lecture structure + stable_id pour le MCP)"
```

- [ ] **Step 8 : Copier le schéma vers le repo MCP**

```bash
cp app/graphql/schema.graphql ../mcp-mes-demarches/schema.graphql
```
(Le repo MCP versionne une copie du contrat. Elle sera commitée en Task 2.)

---

## Task 2 : Scaffolding du repo `../mcp-mes-demarches`

**Files (tous dans `/home/clautier/Rubymine/mcp-mes-demarches`) :**
- Create: `package.json`, `tsconfig.json`, `vitest.config.ts`, `.gitignore`, `.env.example`, `README.md`
- Already present from Task 1 Step 8: `schema.graphql`

- [ ] **Step 1 : `package.json`**

```json
{
  "name": "mcp-mes-demarches",
  "version": "0.1.0",
  "description": "Serveur MCP pour construire des formulaires (démarches) mes-demarches via Claude",
  "type": "module",
  "bin": { "mcp-mes-demarches": "dist/index.js" },
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsx src/index.ts",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "zod": "^3.23.0"
  },
  "devDependencies": {
    "@types/node": "^22.0.0",
    "tsx": "^4.0.0",
    "typescript": "^5.5.0",
    "vitest": "^2.0.0"
  }
}
```

- [ ] **Step 2 : `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": false,
    "resolveJsonModule": true
  },
  "include": ["src"]
}
```

- [ ] **Step 3 : `vitest.config.ts`**

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: { environment: 'node', include: ['src/**/*.test.ts'] }
});
```

- [ ] **Step 4 : `.gitignore`**

```
node_modules/
dist/
.env
*.log
```

- [ ] **Step 5 : `.env.example`**

```
# URL de l'endpoint GraphQL v2 de mes-demarches
MD_GRAPHQL_URL=https://mes-demarches.gov.pf/api/v2/graphql
# Token API administrateur : write_access + scopé à la procédure + (prod) réseau autorisé
MD_API_TOKEN=remplacer_par_votre_token
```

- [ ] **Step 6 : `README.md`** (squelette ; complété en Task 5)

```markdown
# mcp-mes-demarches

Serveur MCP (stdio) qui permet de construire la structure d'une démarche mes-demarches
en langage naturel via Claude. Voir la section « Configuration » (Task 5) pour le branchement.

`schema.graphql` est une copie du contrat GraphQL de mes-demarches (source de vérité :
`mes-demarches/app/graphql/schema.graphql`, régénéré via `bin/rails graphql:schema:dump`).
```

- [ ] **Step 7 : Installer + commit**

```bash
cd /home/clautier/Rubymine/mcp-mes-demarches
npm install
git add package.json package-lock.json tsconfig.json vitest.config.ts .gitignore .env.example README.md schema.graphql
git commit -m "chore: scaffolding du serveur MCP (TypeScript, vitest) + copie du schéma"
```
Expected: `npm install` réussit ; `@modelcontextprotocol/sdk` et `zod` présents dans `node_modules`.

---

## Task 3 : Config + client GraphQL (`src/config.ts`, `src/graphql.ts`)

**Files (dans `../mcp-mes-demarches`) :**
- Create: `src/config.ts`, `src/graphql.ts`, `src/graphql.test.ts`

- [ ] **Step 1 : Écrire le test qui échoue (`src/graphql.test.ts`)**

```ts
import { describe, it, expect, vi } from 'vitest';
import { gqlRequest } from './graphql.js';

describe('gqlRequest', () => {
  const cfg = { url: 'https://md.test/api/v2/graphql', token: 'tok' };

  it('envoie la requête avec le header Bearer et retourne data', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ data: { ping: 'pong' } })
    });
    const data = await gqlRequest(cfg, 'query { ping }', { a: 1 }, fetchMock as unknown as typeof fetch);
    expect(data).toEqual({ ping: 'pong' });
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe(cfg.url);
    expect((init.headers as Record<string, string>).Authorization).toBe('Bearer tok');
    expect(JSON.parse(init.body)).toEqual({ query: 'query { ping }', variables: { a: 1 } });
  });

  it('lève une erreur si la réponse GraphQL contient des errors', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ errors: [{ message: 'boom' }] })
    });
    await expect(gqlRequest(cfg, 'query { x }', {}, fetchMock as unknown as typeof fetch))
      .rejects.toThrow('boom');
  });

  it('lève une erreur sur statut HTTP non ok', async () => {
    const fetchMock = vi.fn().mockResolvedValue({ ok: false, status: 401, text: async () => 'unauthorized' });
    await expect(gqlRequest(cfg, 'q', {}, fetchMock as unknown as typeof fetch))
      .rejects.toThrow(/401/);
  });
});
```

- [ ] **Step 2 : Lancer, vérifier l'échec** : `npm test` → FAIL (module `./graphql.js` absent).

- [ ] **Step 3 : `src/config.ts`**

```ts
export interface Config {
  url: string;
  token: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const url = env.MD_GRAPHQL_URL;
  const token = env.MD_API_TOKEN;
  if (!url) throw new Error('MD_GRAPHQL_URL manquant (URL de l\'endpoint GraphQL v2).');
  if (!token) throw new Error('MD_API_TOKEN manquant (token API administrateur).');
  return { url, token };
}
```

- [ ] **Step 4 : `src/graphql.ts`**

```ts
import type { Config } from './config.js';

// Client GraphQL minimal authentifié par token Bearer. `fetchImpl` injectable pour les tests.
export async function gqlRequest<T = unknown>(
  config: Config,
  query: string,
  variables: Record<string, unknown> = {},
  fetchImpl: typeof fetch = fetch
): Promise<T> {
  const res = await fetchImpl(config.url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${config.token}`
    },
    body: JSON.stringify({ query, variables })
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Erreur HTTP ${res.status} de l'API mes-demarches : ${body}`);
  }

  const payload = (await res.json()) as { data?: T; errors?: Array<{ message: string }> };
  if (payload.errors?.length) {
    throw new Error(payload.errors.map((e) => e.message).join('; '));
  }
  return payload.data as T;
}
```

- [ ] **Step 5 : Lancer, vérifier que ça passe** : `npm test` → 3 tests verts.

- [ ] **Step 6 : Typecheck + commit**

```bash
npm run typecheck
git add src/config.ts src/graphql.ts src/graphql.test.ts
git commit -m "feat: config + client GraphQL authentifié (Bearer)"
```

---

## Task 4 : Définitions des outils (`src/tools.ts`)

**Files (dans `../mcp-mes-demarches`) :**
- Create: `src/tools.ts`, `src/tools.test.ts`

Les 6 outils sont décrits de façon **data-driven**. Chacun a : `name`, `description`, `inputSchema` (Zod), et `run(deps, args)` qui construit l'opération GraphQL, appelle `gqlRequest`, et renvoie un `CallToolResult`. Les mutations renvoient `{ champStableId, errors { message } }` → le helper `mutationResult` formate le résultat (succès ou `isError`).

- [ ] **Step 1 : Écrire les tests qui échouent (`src/tools.test.ts`)**

```ts
import { describe, it, expect, vi } from 'vitest';
import { tools } from './tools.js';

const byName = (n: string) => tools.find((t) => t.name === n)!;

describe('tools', () => {
  it('expose les 6 outils', () => {
    expect(tools.map((t) => t.name).sort()).toEqual(
      ['ajouter_champ', 'definir_condition', 'deplacer_champ', 'lire_demarche', 'modifier_champ', 'supprimer_champ']
    );
  });

  it('ajouter_champ appelle la mutation avec demarche.number et renvoie le stable_id', async () => {
    const gql = vi.fn().mockResolvedValue({ demarcheAjouterChamp: { champStableId: '42', errors: null } });
    const res = await byName('ajouter_champ').run({ gql }, { demarcheNumber: 7, typeChamp: 'text', libelle: 'Nom' });
    const [, variables] = gql.mock.calls[0];
    expect(variables.input.demarche).toEqual({ number: 7 });
    expect(variables.input.typeChamp).toBe('text');
    expect(variables.input.libelle).toBe('Nom');
    expect(res.isError).toBeFalsy();
    expect(res.content[0].text).toContain('42');
  });

  it('remonte les erreurs métier de la mutation comme isError', async () => {
    const gql = vi.fn().mockResolvedValue({ demarcheAjouterChamp: { champStableId: null, errors: [{ message: 'Type de champ inconnu' }] } });
    const res = await byName('ajouter_champ').run({ gql }, { demarcheNumber: 7, typeChamp: 'xxx', libelle: 'N' });
    expect(res.isError).toBe(true);
    expect(res.content[0].text).toContain('Type de champ inconnu');
  });

  it('definir_condition transmet les termes et le combinateur', async () => {
    const gql = vi.fn().mockResolvedValue({ demarcheDefinirCondition: { champStableId: '9', errors: null } });
    await byName('definir_condition').run({ gql }, {
      demarcheNumber: 1, stableId: '9', combinateur: 'OU',
      termes: [{ champSourceStableId: '3', operateur: 'superieur', valeur: '18' }]
    });
    const [, variables] = gql.mock.calls[0];
    expect(variables.input.combinateur).toBe('OU');
    expect(variables.input.termes[0].operateur).toBe('superieur');
  });

  it('lire_demarche fait une query et renvoie la liste JSON', async () => {
    const champs = [{ stableId: '1', typeChamp: 'text', libelle: 'Nom', obligatoire: false, prive: false, parentStableId: null, position: 0, aCondition: false }];
    const gql = vi.fn().mockResolvedValue({ demarcheChamps: champs });
    const res = await byName('lire_demarche').run({ gql }, { demarcheNumber: 5 });
    const [, variables] = gql.mock.calls[0];
    expect(variables.demarche).toEqual({ number: 5 });
    expect(res.content[0].text).toContain('"libelle": "Nom"');
  });
});
```

- [ ] **Step 2 : Lancer, vérifier l'échec** : `npm test` → FAIL (`./tools.js` absent).

- [ ] **Step 3 : `src/tools.ts`**

> ⚠️ Avant d'écrire : ouvrir `schema.graphql` (copié en Task 1) et confirmer les noms EXACTS des types d'input des mutations (`DemarcheAjouterChampInput`, etc.) et de `FindDemarcheInput`. Adapter les chaînes GraphQL si un `graphql_name` diffère.

```ts
import { z } from 'zod';
import { gqlRequest } from './graphql.js';
import type { Config } from './config.js';

export interface ToolDeps {
  // gql(query, variables) -> data ; injecté pour les tests, sinon lie la config réelle.
  gql: (query: string, variables: Record<string, unknown>) => Promise<any>;
}

export interface ToolDef {
  name: string;
  description: string;
  inputSchema: z.ZodRawShape;
  run: (deps: ToolDeps, args: any) => Promise<{ content: Array<{ type: 'text'; text: string }>; isError?: boolean }>;
}

const MUTATION_PAYLOAD = '{ champStableId errors { message } }';

function mutationResult(payload: { champStableId: string | null; errors: Array<{ message: string }> | null }) {
  if (payload.errors && payload.errors.length > 0) {
    return { isError: true, content: [{ type: 'text' as const, text: 'Échec : ' + payload.errors.map((e) => e.message).join(' ; ') }] };
  }
  return { content: [{ type: 'text' as const, text: `OK (champ stable_id = ${payload.champStableId}).` }] };
}

const demarcheInput = (n: number) => ({ number: n });

export const tools: ToolDef[] = [
  {
    name: 'lire_demarche',
    description: "Liste les champs de la révision brouillon d'une démarche (stable_id, type, libellé, condition…). À appeler avant de modifier/déplacer/supprimer un champ existant.",
    inputSchema: { demarcheNumber: z.number().int().describe('Numéro de la démarche.') },
    run: async ({ gql }, { demarcheNumber }) => {
      const query = `query($demarche: FindDemarcheInput!){ demarcheChamps(demarche: $demarche){ stableId typeChamp libelle description obligatoire prive parentStableId position aCondition } }`;
      const data = await gql(query, { demarche: demarcheInput(demarcheNumber) });
      return { content: [{ type: 'text', text: JSON.stringify(data.demarcheChamps, null, 2) }] };
    }
  },
  {
    name: 'ajouter_champ',
    description: "Ajoute un champ à la révision brouillon. Renvoie le stable_id du nouveau champ.",
    inputSchema: {
      demarcheNumber: z.number().int(),
      typeChamp: z.string().describe('text, textarea, integer_number, decimal_number, email, phone, date, yes_no, checkbox, drop_down_list, header_section, repetition, etc.'),
      libelle: z.string(),
      description: z.string().optional(),
      obligatoire: z.boolean().optional(),
      prive: z.boolean().optional(),
      parentStableId: z.string().optional().describe('Pour insérer dans une répétition/bloc.'),
      apresStableId: z.string().optional().describe('Insérer juste après ce champ.')
    },
    run: async ({ gql }, a) => {
      const query = `mutation($input: DemarcheAjouterChampInput!){ demarcheAjouterChamp(input: $input) ${MUTATION_PAYLOAD} }`;
      const input: Record<string, unknown> = { demarche: demarcheInput(a.demarcheNumber), typeChamp: a.typeChamp, libelle: a.libelle };
      for (const k of ['description', 'obligatoire', 'prive', 'parentStableId', 'apresStableId'] as const) {
        if (a[k] !== undefined) input[k] = a[k];
      }
      const data = await gql(query, { input });
      return mutationResult(data.demarcheAjouterChamp);
    }
  },
  {
    name: 'modifier_champ',
    description: "Modifie un champ existant (libellé, description, obligatoire, type). Le changement de type d'un champ déjà publié est restreint aux types compatibles.",
    inputSchema: {
      demarcheNumber: z.number().int(),
      stableId: z.string(),
      libelle: z.string().optional(),
      description: z.string().optional(),
      obligatoire: z.boolean().optional(),
      typeChamp: z.string().optional()
    },
    run: async ({ gql }, a) => {
      const query = `mutation($input: DemarcheModifierChampInput!){ demarcheModifierChamp(input: $input) ${MUTATION_PAYLOAD} }`;
      const input: Record<string, unknown> = { demarche: demarcheInput(a.demarcheNumber), stableId: a.stableId };
      for (const k of ['libelle', 'description', 'obligatoire', 'typeChamp'] as const) {
        if (a[k] !== undefined) input[k] = a[k];
      }
      const data = await gql(query, { input });
      return mutationResult(data.demarcheModifierChamp);
    }
  },
  {
    name: 'deplacer_champ',
    description: "Déplace un champ juste après un autre champ de la même démarche.",
    inputSchema: { demarcheNumber: z.number().int(), stableId: z.string(), apresStableId: z.string() },
    run: async ({ gql }, a) => {
      const query = `mutation($input: DemarcheDeplacerChampInput!){ demarcheDeplacerChamp(input: $input) ${MUTATION_PAYLOAD} }`;
      const data = await gql(query, { input: { demarche: demarcheInput(a.demarcheNumber), stableId: a.stableId, apresStableId: a.apresStableId } });
      return mutationResult(data.demarcheDeplacerChamp);
    }
  },
  {
    name: 'supprimer_champ',
    description: "Supprime un champ de la révision brouillon.",
    inputSchema: { demarcheNumber: z.number().int(), stableId: z.string() },
    run: async ({ gql }, a) => {
      const query = `mutation($input: DemarcheSupprimerChampInput!){ demarcheSupprimerChamp(input: $input) ${MUTATION_PAYLOAD} }`;
      const data = await gql(query, { input: { demarche: demarcheInput(a.demarcheNumber), stableId: a.stableId } });
      return mutationResult(data.demarcheSupprimerChamp);
    }
  },
  {
    name: 'definir_condition',
    description: "Définit (ou retire, si termes vide) la condition d'affichage d'un champ. Les champs sources doivent être situés AVANT le champ conditionné.",
    inputSchema: {
      demarcheNumber: z.number().int(),
      stableId: z.string(),
      combinateur: z.enum(['ET', 'OU']).optional(),
      termes: z.array(z.object({
        champSourceStableId: z.string(),
        operateur: z.enum(['egal', 'different', 'superieur', 'superieur_ou_egal', 'inferieur', 'inferieur_ou_egal', 'inclut', 'exclut', 'dans_archipel', 'hors_archipel', 'dans_departement', 'dans_region']),
        valeur: z.string()
      }))
    },
    run: async ({ gql }, a) => {
      const query = `mutation($input: DemarcheDefinirConditionInput!){ demarcheDefinirCondition(input: $input) ${MUTATION_PAYLOAD} }`;
      const input: Record<string, unknown> = { demarche: demarcheInput(a.demarcheNumber), stableId: a.stableId, termes: a.termes };
      if (a.combinateur !== undefined) input.combinateur = a.combinateur;
      const data = await gql(query, { input });
      return mutationResult(data.demarcheDefinirCondition);
    }
  }
];

// Lie la config réelle pour produire des ToolDeps en prod.
export function realDeps(config: Config): ToolDeps {
  return { gql: (query, variables) => gqlRequest(config, query, variables) };
}
```

- [ ] **Step 4 : Lancer, vérifier que ça passe** : `npm test` → tous verts (graphql + tools).

- [ ] **Step 5 : Typecheck + commit**

```bash
npm run typecheck
git add src/tools.ts src/tools.test.ts
git commit -m "feat: 6 outils MCP (lire + 5 mutations) data-driven, avec tests"
```

---

## Task 5 : Serveur + entrée + doc d'usage

**Files (dans `../mcp-mes-demarches`) :**
- Create: `src/server.ts`, `src/index.ts`
- Modify: `README.md`

- [ ] **Step 1 : `src/server.ts`**

> ⚠️ Confirmer les chemins d'import exacts contre la version installée de `@modelcontextprotocol/sdk` (`node_modules/@modelcontextprotocol/sdk/dist/...` ou ses `exports`). Le pattern ci-dessous (`McpServer` + `registerTool` + `StdioServerTransport`) est l'API stable 1.x.

```ts
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { tools, type ToolDeps } from './tools.js';

export function buildServer(deps: ToolDeps): McpServer {
  const server = new McpServer({ name: 'mcp-mes-demarches', version: '0.1.0' });

  for (const tool of tools) {
    // registerTool attend `inputSchema` comme ZodRawShape (objet brut de zod), PAS un z.object(...).
    // `ToolDef.inputSchema` EST déjà une ZodRawShape → on la passe telle quelle.
    server.registerTool(
      tool.name,
      { description: tool.description, inputSchema: tool.inputSchema },
      async (args: Record<string, unknown>) => tool.run(deps, args)
    );
  }

  return server;
}

export async function startStdio(deps: ToolDeps): Promise<void> {
  const server = buildServer(deps);
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
```

- [ ] **Step 2 : `src/index.ts`**

```ts
#!/usr/bin/env node
import { loadConfig } from './config.js';
import { realDeps } from './tools.js';
import { startStdio } from './server.js';

async function main() {
  const config = loadConfig();
  await startStdio(realDeps(config));
}

main().catch((err) => {
  console.error('[mcp-mes-demarches] erreur fatale :', err instanceof Error ? err.message : err);
  process.exit(1);
});
```

- [ ] **Step 3 : Build + smoke test**

```bash
npm run build
# Smoke : le serveur démarre et attend sur stdio sans crasher (Ctrl-C pour quitter).
MD_GRAPHQL_URL=https://example.test/api/v2/graphql MD_API_TOKEN=dummy node dist/index.js < /dev/null
```
Expected: pas de crash au démarrage (il se ferme proprement quand stdin se ferme). Si l'import du SDK échoue, corriger les chemins d'import selon les `exports` du package installé, puis rebuild.

- [ ] **Step 4 : Compléter le `README.md`**

Y documenter :
- Prérequis : Node ≥ 18, un token API mes-demarches (créé dans le profil admin) avec **write_access**, **scopé à la procédure cible**, et **réseau autorisé** = réseau de l'admin (en prod).
- Build : `npm install && npm run build`.
- Configuration Claude Desktop (`claude_desktop_config.json`) :

```json
{
  "mcpServers": {
    "mes-demarches": {
      "command": "node",
      "args": ["/home/clautier/Rubymine/mcp-mes-demarches/dist/index.js"],
      "env": {
        "MD_GRAPHQL_URL": "https://mes-demarches.gov.pf/api/v2/graphql",
        "MD_API_TOKEN": "votre_token"
      }
    }
  }
}
```
- Claude Code : `claude mcp add mes-demarches -- node /home/clautier/Rubymine/mcp-mes-demarches/dist/index.js` (avec les variables d'env), ou config équivalente.
- Liste des outils + exemple de dialogue (« Ajoute un champ texte “Nom”, puis affiche “SIRET” seulement si le type = entreprise »).

- [ ] **Step 5 : Typecheck + commit**

```bash
npm run typecheck && npm test
git add src/server.ts src/index.ts README.md
git commit -m "feat: bootstrap serveur MCP (stdio) + entrée + doc d'usage Claude"
```

---

## Self-Review (effectuée à l'écriture)

- **Couverture :** Task 1 ferme le manque de `stable_id` côté lecture (query PF isolée, sans toucher upstream). Tasks 2-5 livrent le serveur MCP : config/auth (T3, testé), 6 outils (T4, testés en isolant `gql`), bootstrap stdio + doc (T5). La boucle MVP « parler à Claude → construire un formulaire » est complète (lire + ajouter/modifier/déplacer/supprimer + condition).
- **Placeholders :** aucun. Deux points à CONFIRMER explicitement à l'implémentation (signalés en ⚠️) : (a) les noms exacts des types d'input GraphQL dans `schema.graphql` ; (b) les chemins d'import du SDK MCP installé. Ce sont des vérifications, pas des trous de spec.
- **Cohérence des types :** les noms d'outils, les clés de payload (`champStableId`, `errors`), et les noms d'arguments camelCase correspondent aux mutations des Plans A & B et à la query de Task 1. `ToolDeps.gql` est injecté → outils testables sans réseau.

## Hors périmètre (suite)

- Configuration des options par type (valeurs de listes, binding référentiel) → increment (cf. spec §8 : scalaire JSON + descripteur).
- Plan C (description dynamique types/référentiels) → confort de guidage, non requis pour le MVP.
- Phase B (MCP hébergé + OAuth) → ultérieur.
- `output schema` structuré des outils MCP, pagination, gestion fine des répétitions imbriquées → non-MVP.
