# Champ formule, PR 1 : graphe unique — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un seul graphe de dépendances des formules par révision et une seule analyse des références `{…}` ; le moteur de calcul actuel est conservé mais calcule dans l'ordre du graphe et suit l'aval des formules à drapeau.

**Architecture:** Trois objets PF dans `app/services/` : `FormulaReferences` (découpe une expression en références), `FormulaReferenceScope` (ce qu'une formule a le droit de référencer, code déménagé de la coordonnée), `FormulaDependencyGraph` (nœuds, arêtes, ordre de calcul, fermeture aval, cycle, référence vers l'avant). `ProcedureRevision#formula_graph` est la seule porte d'entrée. Le concern de recalcul, la validation du type de champ et le rendu Turbo interrogent le graphe ; les méthodes de dépendances quittent `champ.rb`, `procedure_revision.rb` et `procedure_revision_type_de_champ.rb`.

**Tech Stack:** Ruby 3.3, Rails 7, RSpec, Capybara + Playwright (headless), Dentaku.

**Spec:** `docs/superpowers/specs/2026-11-27-formule-refonte-graphe-et-passe-design.md` (§ 6.1, § 7 « PR 1 », § 8 « Nouveaux, PR 1 »). À lire avant de commencer.

## Global Constraints

- Branche `feature/formule-graphe-unique`, créée depuis `devpf` à jour (qui contient la PR #642). PR vers `devpf`, merge simple (pas de squash), `gh pr create --repo govpf/mes-demarches`.
- Aucune migration, aucun changement de stockage, aucune tâche de maintenance. Le format de `formule_deps` ne change pas.
- Fichiers upstream (`champ.rb`, `procedure_revision.rb`, `procedure_revision_type_de_champ.rb`, `turbo_champs_concern.rb`) : il n'y reste que des accroches d'**une ligne taguée `# pf:`**. Toute la logique vit dans des fichiers PF.
- Ne pas recopier de logique upstream. Ne pas ajouter de callback ActiveRecord.
- Les signatures publiques `refresh_formulas_after`, `compute_initial_formulas`, `compute_formulas_in_order`, `refresh_state_dependent_formulas`, `refresh_clock_dependent_formulas(scope:)`, `refresh_formulas_with_identite_dependents` ne changent pas.
- La règle de visibilité des références reste **strictement** celle d'aujourd'hui : aucune expression acceptée aujourd'hui ne doit être refusée, ni l'inverse.
- Le format hérité `{123}` n'est pas reconnu par la nouvelle analyse (zéro expression en production). La branche héritée de `FormulaCalculationService` et `TypesDeChamp::FormulaValidator` ne sont pas modifiés au-delà de ce que ce plan indique (PR 2 et chantier validateurs).
- Hors périmètre de cette PR : la passe accumulante, l'accroche de `project_champ`, la règle des dossiers terminés, l'enregistrement des formules-ligne, la fusion des validateurs.
- Tests : en local, seulement les specs citées par chaque tâche. La suite complète tourne dans la CI de la PR. Specs système en headless (`NO_HEADLESS=` en préfixe de commande).
- Textes d'interface en français avec l'apostrophe typographique « ’ ». Commentaires de code en français, tagués `# pf:`.
- Commits : un par tâche, message en français au format `refactor(formule): …` / `fix(formule): …`, terminé par la ligne `Co-Authored-By` de la session.

## Review Focus

1. **Expression d'un type de champ publié modifiée en place dans une spec** (`tdc.update!(formule_expression:)` sur une révision déjà chargée) : le graphe mémoïsé d'une révision verrouillée ne doit pas servir un état périmé à un dossier chargé ensuite. Test en tâche 3.
2. **Formule sans expression** (champ formule tout juste ajouté, expression vide) : le graphe se construit, la formule est dans l'ordre, sans arête. Test en tâche 3.
3. **Référence vers un type de champ absent de la révision** (champ supprimé, expression pas encore corrigée) : pas d'exception à la construction ni dans la fermeture aval ; `forward_reference?` répond vrai comme aujourd'hui. Test en tâche 3.
4. **Annotation privée dans un bloc privé qui agrège un bloc public** : l'ordre place tout le public avant, la fermeture aval atteint l'annotation depuis un sous-champ du bloc public. Test en tâche 3.
5. **Source sur le tampon usager** (`user:buffer`) : les formules privées en aval restent exclues de la cascade, comme aujourd'hui. Test en tâche 4.

---

## Structure des fichiers

| Fichier | Rôle |
|---|---|
| `app/services/formula_references.rb` (créé) | Seule analyse des références `{…}` d'une expression. |
| `app/services/formula_reference_scope.rb` (créé) | Ce qu'une formule peut référencer depuis sa coordonnée (code déménagé). |
| `app/services/formula_dependency_graph.rb` (créé) | Graphe d'une révision : nœuds, arêtes, ordre, fermeture aval, validation structurelle. |
| `app/models/procedure_revision.rb` | + accroche `formula_graph` ; − `dependent_formulas`. |
| `app/models/procedure_revision_type_de_champ.rb` | Trois méthodes réduites à une ligne de délégation. |
| `app/models/champ.rb` | − cinq méthodes de dépendances. |
| `app/models/concerns/dossier_formula_refresh_concern.rb` | Ordre du graphe, fermeture aval, méthode pour Turbo. |
| `app/models/types_de_champ/formule_type_de_champ.rb` | Cycle, référence vers l'avant et `formule_deps['champs']` via le graphe et l'analyse. |
| `app/controllers/concerns/turbo_champs_concern.rb` | La ligne PF existante appelle le dossier. |
| `app/services/formula_system_columns.rb`, `formula_expression_service.rb`, `formula_calculation_service.rb`, `app/validators/types_de_champ/formula_validator.rb` | Leur expression régulière `{…}` est remplacée par un appel à `FormulaReferences`. |

---

### Task 1: `FormulaReferences`, l'analyse unique

**Files:**
- Create: `app/services/formula_references.rb`
- Test: `spec/services/formula_references_spec.rb`
- Modify: `app/services/formula_system_columns.rb:70-72`, `app/services/formula_expression_service.rb:9,35`, `app/services/formula_calculation_service.rb:448,472`, `app/validators/types_de_champ/formula_validator.rb:62`

**Interfaces:**
- Produces:
  - `FormulaReferences::Ref = Data.define(:raw, :stable_id, :sub_stable_id, :path)` — `raw` : texte entre accolades, espaces de bord retirés ; `stable_id` : entier pour `{tdcN…}`, `nil` sinon ; `sub_stable_id` : entier pour `{tdcN/sub_M}`, `nil` sinon ; `path` : chaîne pour `{tdcN/chemin}` hors `sub_`, `nil` sinon. Méthodes `champ?` (`stable_id` présent) et `sub_champ?` (`sub_stable_id` présent).
  - `FormulaReferences.scan(expression) → Array<Ref>` (ordre d'apparition, doublons conservés, `[]` si expression vide ou `nil`).
  - `FormulaReferences.stable_ids(expression) → Array<Integer>` (les `stable_id`, sans doublon, triés ; n'inclut pas les `sub_stable_id`).
  - `FormulaReferences.gsub(expression) { |ref, match| String } → String` (`match` : le texte complet accolades comprises).

- [ ] **Step 1: Écrire la spec**

```ruby
describe FormulaReferences do
  describe '.scan' do
    it 'reconnaît les quatre formes de référence' do
      refs = described_class.scan('{tdc12} + {tdc34/code_postal} + SOMME({tdc56/sub_78}) + { dossier_number }')
      expect(refs.map(&:to_h)).to eq([
        { raw: 'tdc12', stable_id: 12, sub_stable_id: nil, path: nil },
        { raw: 'tdc34/code_postal', stable_id: 34, sub_stable_id: nil, path: 'code_postal' },
        { raw: 'tdc56/sub_78', stable_id: 56, sub_stable_id: 78, path: nil },
        { raw: 'dossier_number', stable_id: nil, sub_stable_id: nil, path: nil },
      ])
    end

    it 'ne reconnaît pas le format hérité {123} comme une référence de champ' do
      expect(described_class.scan('{123}').first.stable_id).to be_nil
    end

    it 'renvoie [] pour nil et pour une expression sans accolades' do
      expect(described_class.scan(nil)).to eq([])
      expect(described_class.scan('1 + 1')).to eq([])
    end
  end

  it '.stable_ids dédoublonne et trie, sans les sous-champs' do
    expect(described_class.stable_ids('{tdc9} * {tdc3} + {tdc9/sub_4}')).to eq([3, 9])
  end

  it '.gsub remplace chaque référence par le résultat du bloc' do
    out = described_class.gsub('{tdc1} + {dossier_number}') { |ref, match| ref.champ? ? 'X' : match }
    expect(out).to eq('X + {dossier_number}')
  end
end
```

- [ ] **Step 2: Lancer, constater l'échec**

Run: `bundle exec rspec spec/services/formula_references_spec.rb`
Expected: FAIL, `uninitialized constant FormulaReferences`

- [ ] **Step 3: Implémenter `FormulaReferences`** (module à méthodes de module, une seule constante `PATTERN = /\{([^}]+)\}/`).

- [ ] **Step 4: Lancer, constater le succès**

Run: `bundle exec rspec spec/services/formula_references_spec.rb`
Expected: PASS

- [ ] **Step 5: Brancher les quatre analyses existantes**

Remplacer chaque expression régulière par l'appel, sans changer le corps des blocs (ils reçoivent `ref.raw` là où ils lisaient `$1.strip`, et `match` là où ils renvoyaient l'original) :
- `FormulaSystemColumns.references_trigger?` → `FormulaReferences.scan(expression).any? { trigger(_1.raw) == trigger }`
- `FormulaExpressionService.convert_to_stable_ids` et `.convert_to_libelles` → `FormulaReferences.gsub`
- `FormulaCalculationService#resolve_field_references` et `#resolve_column_references` → `FormulaReferences.gsub`
- `TypesDeChamp::FormulaValidator#validate_column_references` ligne 62 → `FormulaReferences.scan(tdc.formule_expression).map(&:raw)`

Ne pas toucher `formula_calculation_service.rb:189` (masquage pour la détection du `=` seul) ni `formula_validator.rb:125-126` (ancien validateur par libellé).

- [ ] **Step 6: Non-régression**

Run: `bundle exec rspec spec/services/formula_expression_service_spec.rb spec/services/formula_calculation_service_spec.rb spec/services/formula_column_resolver_spec.rb spec/models/types_de_champ/formule_type_de_champ_spec.rb`
Expected: PASS, mêmes compteurs qu'avant la tâche

- [ ] **Step 7: Commit** — `refactor(formule): une seule analyse des références {…}`

---

### Task 2: `FormulaReferenceScope`, la règle de visibilité hors de la coordonnée

**Files:**
- Create: `app/services/formula_reference_scope.rb`
- Test: `spec/services/formula_reference_scope_spec.rb`
- Modify: `app/models/procedure_revision_type_de_champ.rb:107-212` (méthodes `available_parent_columns_for_formula`, `aggregable_repetition_types_de_champ`, `available_columns_for_formula`)

**Interfaces:**
- Produces:
  - `FormulaReferenceScope.new(coordinate)` — `coordinate` : un `ProcedureRevisionTypeDeChamp`.
  - `#parent_columns → Array<Column>` (corps actuel de `available_parent_columns_for_formula`)
  - `#columns → Array<Column>` (corps actuel de `available_columns_for_formula`)
  - `#aggregable_repetitions → Array<TypeDeChamp>` (corps actuel de `aggregable_repetition_types_de_champ`)
  - `#allowed_stable_ids → Set<Integer>` : `stable_id` des `Columns::ChampColumn` de `#columns`, plus ceux de `#aggregable_repetitions`.
  - Sur la coordonnée, trois délégations d'une ligne, mêmes noms qu'aujourd'hui.

- [ ] **Step 1: Écrire la spec de caractérisation**

Une démarche brouillon avec : public `[Nombre A, Formule F1, Bloc B(Nombre P, Formule L), Formule F2]`, privé `[Nombre N, Formule G]`. Assertions sur `allowed_stable_ids` :

```ruby
it 'formule publique : champs publics précédents et blocs précédents' do
  expect(scope_of(f2).allowed_stable_ids).to eq(Set[a.stable_id, f1.stable_id, p.stable_id, l.stable_id, bloc.stable_id])
end
it 'première formule publique : rien après elle' do
  expect(scope_of(f1).allowed_stable_ids).to eq(Set[a.stable_id])
end
it 'formule-ligne : frères précédents de la ligne et racine avant le bloc' do
  expect(scope_of(l).allowed_stable_ids).to eq(Set[p.stable_id, a.stable_id, f1.stable_id])
end
it 'annotation privée : tout le public, les annotations précédentes, les blocs publics' do
  expect(scope_of(g).allowed_stable_ids).to eq(Set[a.stable_id, f1.stable_id, p.stable_id, l.stable_id, f2.stable_id, n.stable_id, bloc.stable_id])
end
it 'renvoie un périmètre vide pour un champ non formule' do
  expect(scope_of(a).columns).to eq([])
end
```

Avant d'écrire le code, faire tourner ces attentes contre l'implémentation actuelle (via `coordinate.available_columns_for_formula` et `aggregable_repetition_types_de_champ`) : si une attente diffère du comportement actuel, **c'est l'attente qu'on corrige**, la règle ne change pas.

- [ ] **Step 2: Lancer, constater l'échec**

Run: `bundle exec rspec spec/services/formula_reference_scope_spec.rb`
Expected: FAIL, `uninitialized constant FormulaReferenceScope`

- [ ] **Step 3: Déménager le code**

Déplacer les trois corps de méthode dans `FormulaReferenceScope`, sans réécriture (les appels implicites à `revision`, `procedure`, `position`, `parent`, `private?`, `in_repetition?`, `parent_type_de_champ`, `upper_coordinates`, `type_de_champ` passent par la coordonnée). Dans `procedure_revision_type_de_champ.rb`, il reste :

```ruby
  # pf: règle de visibilité des formules — FormulaReferenceScope
  def available_parent_columns_for_formula = FormulaReferenceScope.new(self).parent_columns
  def available_columns_for_formula = FormulaReferenceScope.new(self).columns
  def aggregable_repetition_types_de_champ = FormulaReferenceScope.new(self).aggregable_repetitions
```

`in_repetition?`, `available_in_repetition_context?` et `check_collision_warning` restent en place (seul l'ancien validateur les appelle ; chantier validateurs).

- [ ] **Step 4: Lancer la spec et la non-régression**

Run: `bundle exec rspec spec/services/formula_reference_scope_spec.rb spec/models/procedure_revision_type_de_champ_spec.rb spec/services/formula_ai_prompt_service_spec.rb spec/components/types_de_champ_editor`
Expected: PASS

- [ ] **Step 5: Commit** — `refactor(formule): règle de visibilité des références dans FormulaReferenceScope`

---

### Task 3: `FormulaDependencyGraph`

**Files:**
- Create: `app/services/formula_dependency_graph.rb`
- Test: `spec/services/formula_dependency_graph_spec.rb`
- Modify: `app/models/procedure_revision.rb` (ajout de l'accroche près de `coordinate_for` ; suppression de `dependent_formulas`, lignes 228-236)

**Interfaces:**
- Consumes: `FormulaReferences.scan`, `FormulaReferenceScope#allowed_stable_ids`.
- Produces:
  - `ProcedureRevision#formula_graph → FormulaDependencyGraph` — une ligne taguée `# pf:` ; mémoïsée sur l'instance **uniquement si `locked?`**, reconstruite à chaque appel sur une révision brouillon.
  - `FormulaDependencyGraph::Node = Data.define(:stable_id, :type_de_champ, :level, :bloc_stable_id)` — `level` ∈ `:public`, `:private`, `:row` ; `bloc_stable_id` renseigné seulement pour `:row`.
  - `FormulaDependencyGraph::Edge = Data.define(:kind, :stable_id, :sub_stable_id)` — `kind` ∈ `:champ` (`{tdcN}`, `{tdcN/chemin}`), `:bloc` (`{tdcBloc}` où N est un bloc répétable), `:sub_champ` (`{tdcBloc/sub_M}`).
  - `#any_formula? → Boolean`
  - `#node(stable_id) → Node | nil`
  - `#formula_stable_ids → Array<Integer>` dans l'ordre de calcul.
  - `#formula_types_de_champ(only: nil) → Array<TypeDeChamp>` dans l'ordre de calcul ; `only` : `Enumerable` de `stable_id` ou `nil`.
  - `#edges(stable_id) → Array<Edge>` (`[]` si inconnu ou sans expression).
  - `#downstream_of(source_stable_ids) → Array<Integer>` : formules à recalculer, dans l'ordre de calcul.
  - `#flagged(flag, private_only: false) → Array<Integer>` : formules dont `formule_deps[flag]` est vrai, dans l'ordre de calcul ; `flag` ∈ `'has_clock'`, `'has_state'`, `'has_identite'`.
  - `#flagged_with_downstream(flag, private_only: false) → Array<Integer>` : `flagged` plus leur aval, sans doublon, dans l'ordre de calcul.
  - `#circular_reference?(stable_id, expression) → Boolean`
  - `#forward_reference?(stable_id, expression) → Boolean`

**Règles à implémenter** (la signature ne les détermine pas) :

- *Ordre de calcul* : parcourir `revision.revision_types_de_champ_public` (déjà triés par position) ; pour un bloc répétable, insérer à sa place ses enfants dans l'ordre de leur position ; puis faire de même avec `revision_types_de_champ_private`. Ne garder que les formules. Ne jamais partir de `revision.types_de_champ` (liste à plat, cause du défaut D1).
- *Fermeture aval* : graines = les `source_stable_ids`, plus le bloc parent de chaque graine qui est un sous-champ. Une formule dépend d'un `stable_id` X si l'une de ses arêtes a `stable_id == X` (pour `:bloc` et `:sub_champ`, X est le bloc). Parcours en largeur ; quand une formule de niveau `:row` est atteinte, ajouter aussi son `bloc_stable_id` aux sources à suivre. Résultat trié par l'ordre de calcul. Une graine qui est elle-même une formule n'est dans le résultat que si le parcours la ré-atteint.
- *Cycle* : parcours des arêtes depuis `stable_id`, en utilisant `expression` pour ce nœud et l'expression enregistrée pour les autres ; vrai si le parcours revient sur `stable_id`. Faux si `stable_id` est `nil`.
- *Référence vers l'avant* : vrai si l'une des références de champ de `expression` a un `stable_id` hors de `FormulaReferenceScope.new(revision.coordinate_for(tdc)).allowed_stable_ids`. Faux si `stable_id` est `nil` ou sans coordonnée.
- Les arêtes sont lues dans l'expression (`FormulaReferences`), les drapeaux dans `formule_deps`.

- [ ] **Step 1: Écrire la spec**

Démarche publiée, public `[Nombre A (0), Formule F (1), Bloc B (2) : enfants [Formule L (0), Nombre P (1)], Formule T (3)]`, privé `[Formule G (0), Nombre N (1), Bloc privé BP (2) : enfants [Formule LP (0)]]`. Expressions : `F = {A} * 2`, `L = {F} * 10`, `T = SOMME({B/sub_L}) + NB({B})`, `G = {F} + 1`, `LP = SOMME({B/sub_L})` ; écrites avec `update!` avant toute lecture de la révision.

```ruby
it "calcule le public déplié puis le privé" do
  expect(graph.formula_stable_ids).to eq([f, l, t, g, lp].map(&:stable_id))
end
it 'classe les nœuds par niveau' do
  expect(graph.node(f.stable_id).level).to eq(:public)
  expect(graph.node(g.stable_id).level).to eq(:private)
  expect(graph.node(l.stable_id)).to have_attributes(level: :row, bloc_stable_id: b.stable_id)
end
it 'distingue les trois sortes de dépendance' do
  expect(graph.edges(g.stable_id).map(&:to_h)).to eq([{ kind: :champ, stable_id: f.stable_id, sub_stable_id: nil }])
  expect(graph.edges(t.stable_id).map(&:to_h)).to eq([
    { kind: :sub_champ, stable_id: b.stable_id, sub_stable_id: l.stable_id },
    { kind: :bloc, stable_id: b.stable_id, sub_stable_id: nil },
  ])
end
it "suit l'aval, bloc parent d'une formule-ligne compris" do
  expect(graph.downstream_of([a.stable_id])).to eq([f, l, t, g, lp].map(&:stable_id))
end
it "part du bloc parent quand la source est un sous-champ" do
  expect(graph.downstream_of([p.stable_id])).to eq([t, lp].map(&:stable_id))
end
it "ne renvoie rien pour une source sans aval" do
  expect(graph.downstream_of([n.stable_id])).to eq([])
end
it "ajoute l'aval des formules à drapeau" do
  f.update!(formule_expression: 'ANNEE(AUJOURDHUI())')
  fresh = Procedure.find(procedure.id).active_revision.formula_graph
  expect(fresh.flagged('has_clock')).to eq([f.stable_id])
  expect(fresh.flagged_with_downstream('has_clock')).to eq([f, l, t, g, lp].map(&:stable_id))
  expect(fresh.flagged_with_downstream('has_clock', private_only: true)).to eq([])
end
it 'détecte une auto-référence et un cycle indirect' do
  expect(graph.circular_reference?(f.stable_id, "{tdc#{f.stable_id}} + 1")).to be true
  expect(graph.circular_reference?(f.stable_id, "{tdc#{g.stable_id}} + 1")).to be true
  expect(graph.circular_reference?(g.stable_id, "{tdc#{f.stable_id}} + 1")).to be false
end
it "détecte une référence vers l'avant" do
  expect(graph.forward_reference?(f.stable_id, "{tdc#{t.stable_id}}")).to be true
  expect(graph.forward_reference?(l.stable_id, "{tdc#{f.stable_id}}")).to be false
end
```

Tests du Review Focus, dans la même spec :

```ruby
it 'accepte une formule sans expression' do            # focus 2
  f.update_column(:options, f.options.merge('formule_expression' => nil))
  fresh = Procedure.find(procedure.id).active_revision.formula_graph
  expect(fresh.formula_stable_ids).to include(f.stable_id)
  expect(fresh.edges(f.stable_id)).to eq([])
end
it "tolère une référence vers un champ absent de la révision" do   # focus 3
  expect(graph.downstream_of([999_999])).to eq([])
  expect(graph.forward_reference?(f.stable_id, '{tdc999999}')).to be true
  expect(graph.circular_reference?(f.stable_id, '{tdc999999}')).to be false
end
it "atteint une formule-ligne privée depuis un sous-champ de bloc public" do   # focus 4
  expect(graph.downstream_of([p.stable_id])).to include(lp.stable_id)
  expect(graph.formula_stable_ids.index(lp.stable_id)).to be > graph.formula_stable_ids.index(t.stable_id)
end
it "mémoïse sur une révision verrouillée, pas sur un brouillon" do   # focus 1
  published = procedure.active_revision
  expect(published.formula_graph).to equal(published.formula_graph)
  draft = procedure.draft_revision
  expect(draft.formula_graph).not_to equal(draft.formula_graph)
end
it "sert un graphe à jour à un dossier chargé après la modification d'une expression" do   # focus 1
  procedure.active_revision.formula_graph
  g.update!(formule_expression: "{tdc#{a.stable_id}} + 1")
  dossier = create(:dossier, procedure:)
  expect(dossier.revision.formula_graph.edges(g.stable_id).map(&:stable_id)).to eq([a.stable_id])
end
```

- [ ] **Step 2: Lancer, constater l'échec**

Run: `bundle exec rspec spec/services/formula_dependency_graph_spec.rb`
Expected: FAIL, `undefined method 'formula_graph'`

- [ ] **Step 3: Implémenter `FormulaDependencyGraph` et l'accroche**

Dans `procedure_revision.rb` :

```ruby
  # pf: graphe de dépendances des formules (FormulaDependencyGraph)
  def formula_graph = locked? ? (@formula_graph ||= FormulaDependencyGraph.new(self)) : FormulaDependencyGraph.new(self)
```

Supprimer `ProcedureRevision#dependent_formulas` (aucun appelant). Le graphe construit tout dans `initialize` à partir de `revision.revision_types_de_champ` (une seule lecture) et ne garde aucun état modifiable.

- [ ] **Step 4: Lancer, constater le succès**

Run: `bundle exec rspec spec/services/formula_dependency_graph_spec.rb spec/models/procedure_revision_spec.rb`
Expected: PASS

- [ ] **Step 5: Commit** — `feat(formule): graphe de dépendances unique par révision`

---

### Task 4: le moteur de recalcul suit le graphe (D1, D3)

**Files:**
- Modify: `app/models/concerns/dossier_formula_refresh_concern.rb`
- Modify: `app/models/champ.rb:371-492` (suppression)
- Modify: `app/controllers/concerns/turbo_champs_concern.rb:14-16`
- Test: `spec/models/champs/formule_cascade_audit_spec.rb`, `spec/models/concerns/dossier_formula_refresh_concern_spec.rb`
- Modify (specs existantes) : `spec/models/champ_spec.rb:731-820`, `spec/system/users/identifiant_entreprise_spec.rb:183`

**Interfaces:**
- Consumes: `revision.formula_graph` et ses méthodes `any_formula?`, `node`, `formula_types_de_champ(only:)`, `downstream_of`, `flagged`, `flagged_with_downstream`.
- Produces: `Dossier#formula_champs_downstream_of(champ) → Array<Champ>` (public, dans le concern) : les champs formule à re-rendre après la modification de `champ`, dans l'ordre de calcul, limités à la ligne de `champ` plus les champs hors bloc quand `champ.row_id` est présent, sans doublon de `public_id`. Remplace `Champ#all_dependent_formula_champs`.

- [ ] **Step 1: Écrire les tests D1 dans `formule_cascade_audit_spec.rb`**

Nouveau `describe "ordre de calcul entre niveaux (graphe)"`, avec les helpers existants `set_formule_expression` et le motif `set_coef` du contexte « formule-ligne qui lit une formule racine ».

Cas 1 — annotation privée en première position qui lit une formule publique placée plus bas :
public `[Nombre 'Source', Formule 'Double']`, privé `[Formule 'Plus un']` ; `Double = {Source} * 2`, `Plus un = {Double} + 1` ; dossier `:en_construction`.

```ruby
it "recalcule l'annotation après la formule publique qu'elle lit" do
  set_source(5)
  set_source(10)
  expect(value_of(double_tdc)).to eq('20')
  expect(value_of(plus_un_tdc)).to eq('21')
end
```

Cas 2 — formule-ligne placée en tête de son bloc qui lit une formule racine :
public `[Nombre 'Coef', Formule 'Taux', Bloc 'Lignes' : enfants [Formule 'Montant', Nombre 'Prix']]` ; `Taux = {Coef} * 2`, `Montant = {Taux} * 10`. Une ligne créée avec `dossier.repetition_add_row`, et le champ `Montant` de cette ligne enregistré par `dossier.champ_for_update(montant_tdc, row_id:, updated_by: 'test').save!`.

```ruby
it "recalcule la formule-ligne après la formule racine qu'elle lit" do
  set_coef(1)
  set_coef(3)
  expect(value_of(taux_tdc)).to eq('6')
  expect(value_of(montant_tdc, row_id:)).to eq('60')
end
```

`value_of` relit le champ en base (`dossier.reload.champs.find { … }.read_attribute(:value)`).

- [ ] **Step 2: Écrire les tests D3 dans `dossier_formula_refresh_concern_spec.rb`**

Nouveau `describe "aval des formules à drapeau"`, annotations privées `[Formule 'A', Formule 'B']`, `B = {A} + 1`, dossier `:en_construction`, valeurs initiales posées par `dossier.compute_formulas_in_order`.

```ruby
it 'horloge : B suit A après le recalcul de nuit' do
  set_expression(a_tdc, 'ANNEE(AUJOURDHUI())')
  travel_to(Time.zone.local(2026, 6, 15, 12)) { fresh_dossier.compute_formulas_in_order }
  travel_to(Time.zone.local(2027, 1, 2, 12)) { fresh_dossier.refresh_clock_dependent_formulas(scope: :private_only) }
  expect(value_of(b_tdc)).to eq('2028')
end

it "état : B suit A après un changement d'horodatage" do
  set_expression(a_tdc, 'ANNEE({dossier_en_instruction_at})')
  dossier.update_column(:en_instruction_at, Time.zone.local(2026, 6, 15, 12))
  fresh_dossier.compute_formulas_in_order
  dossier.update_column(:en_instruction_at, Time.zone.local(2030, 6, 15, 12))
  fresh_dossier.refresh_state_dependent_formulas
  expect(value_of(b_tdc)).to eq('2031')
end

it "identité : B suit A après un changement d'identité" do   # démarche :for_individual, dossier :with_individual
  set_expression(a_tdc, 'CONCATENER("Bonjour ", {individual_last_name})')
  set_expression(b_tdc, 'CONCATENER({A}, " !")')
  fresh_dossier.compute_formulas_in_order
  dossier.individual.update!(nom: 'Martin')
  fresh_dossier.refresh_formulas_with_identite_dependents
  expect(value_of(b_tdc)).to eq('Bonjour MARTIN !')
end
```

`set_expression` passe par `FormulaExpressionService.convert_to_stable_ids` puis `update!` ; `fresh_dossier` est `Dossier.find(dossier.id)`.

Test du Review Focus 5, dans le même fichier :

```ruby
it 'source sur le tampon usager : les formules privées en aval ne sont pas recalculées' do
  # public [Nombre 'Source', Formule 'Double'], privé [Formule 'Plus un'], dossier en_construction
  champ = dossier.with_update_stream(dossier.user) { dossier.champ_for_update(source_tdc, row_id: nil, updated_by: 'test') }
  champ.update!(value: '10')
  expect { dossier.refresh_formulas_after(champ) }.not_to change { value_of(plus_un_tdc) }
end
```

(Si `with_update_stream` n'a pas cette forme, reprendre la mise en place d'une spec existante qui écrit sur `Champ::USER_BUFFER_STREAM`.)

- [ ] **Step 3: Lancer, noter les échecs**

Run: `bundle exec rspec spec/models/champs/formule_cascade_audit_spec.rb spec/models/concerns/dossier_formula_refresh_concern_spec.rb`
Expected: les deux cas D1 et les trois cas D3 échouent (valeur aval périmée) ; le cas du tampon passe déjà.

Le défaut D1 a été lu dans le code sans être reproduit. Si un cas D1 passe avant toute modification, le garder comme test de non-régression et l'écrire dans la description de la PR : ne pas le tordre pour le faire échouer.

- [ ] **Step 4: Modifier le concern**

- `compute_formulas_in_order` : la liste des formules devient `revision.formula_graph.formula_types_de_champ(only: only)`. Rien d'autre ne change dans la méthode.
- `refresh_formulas_after` : court-circuit par `graph.any_formula?` ; `dependent_stable_ids = graph.downstream_of([champ.stable_id])` ; le filtre des formules privées sur tampon lit `graph.node(sid).type_de_champ.private?`. Le reste (flux, `seed_overrides`, `row_id`) ne change pas.
- `refresh_formulas_with_identite_dependents` : `only` devient `graph.flagged_with_downstream('has_identite')`.
- `refresh_state_dependent_formulas` et `refresh_clock_dependent_formulas(scope:)` appellent une méthode privée `refresh_flagged_formulas(flag, private_only: false)` qui remplace `refresh_formulas_matching` : formules de `graph.flagged_with_downstream(flag, private_only:)` dans l'ordre du graphe ; un seul `FormulaCalculationService.new(self, value_overrides: overrides)` dont le hash `overrides` reçoit chaque valeur calculée (c'est ce qui donne la valeur fraîche à l'aval) ; écriture inchangée (`update_column(:value, …)` si la valeur diffère, `rescue StandardError` par champ avec le même message de log).
- `has_state_dependent_formula?` : `revision.formula_graph.flagged('has_state').any?`.
- Ajouter `formula_champs_downstream_of(champ)` (corps de l'actuel `Champ#all_dependent_formula_champs`, la liste de `stable_id` venant de `graph.downstream_of([champ.stable_id])`).
- Mettre à jour le commentaire d'en-tête de `compute_formulas_in_order` : l'ordre vient du graphe, plus de l'invariant « position = ordre topologique ».

- [ ] **Step 5: Retirer les méthodes de `champ.rb` et rebrancher Turbo**

Supprimer de `champ.rb` : `dependent_formula_champs`, `dependent_formula_stable_ids`, `all_dependent_formula_champs`, `dependency_seed_stable_ids`, `dependent_formula_champs_from`. Ne pas toucher `dependent_referentiel_filter_champs`.

Dans `turbo_champs_concern.rb`, la ligne PF devient :

```ruby
    to_update += updated_champs.flat_map { _1.dossier.formula_champs_downstream_of(_1) }.uniq
```

Specs existantes : supprimer le `describe '#dependent_formula_champs'` de `spec/models/champ_spec.rb` (méthode sans appelant, comportement couvert par la spec du graphe) ; dans `spec/system/users/identifiant_entreprise_spec.rb:183`, remplacer par `dossier.revision.formula_graph.downstream_of([siret_champ.stable_id]).empty?`.

- [ ] **Step 6: Lancer, constater le succès**

Run: `bundle exec rspec spec/models/champs/formule_cascade_audit_spec.rb spec/models/concerns/dossier_formula_refresh_concern_spec.rb spec/models/concerns/dossier_clone_concern_spec.rb spec/models/champ_spec.rb spec/services/formula_calculation_service_spec.rb spec/jobs/cron/refresh_clock_dependent_formulas_job_spec.rb spec/graphql/annotation_spec.rb`
Expected: PASS (le test `pending` du brouillon reste `pending` : il relève de la PR 2)

Run: `grep -rnE "dependent_formula_(champs|stable_ids)|all_dependent_formula_champs|dependency_seed_stable_ids|refresh_formulas_matching" app spec lib`
Expected: aucune ligne, hors commentaires historiques des specs à mettre à jour s'ils nomment une méthode supprimée.

- [ ] **Step 7: Commit** — `fix(formule): calcul dans l'ordre du graphe et suivi de l'aval des formules à drapeau`

---

### Task 5: la validation du type de champ s'appuie sur le graphe

**Files:**
- Modify: `app/models/types_de_champ/formule_type_de_champ.rb:278-393`
- Test: `spec/models/types_de_champ/formule_type_de_champ_spec.rb`

**Interfaces:**
- Consumes: `FormulaReferences.scan`, `FormulaReferences.stable_ids`, `FormulaReferences.gsub`, `graph.circular_reference?(stable_id, expression)`, `graph.forward_reference?(stable_id, expression)`.
- Produces: rien de nouveau. `formule_deps` garde son format (`'champs'` : `stable_id` triés sans doublon, plus `has_state`, `has_identite`, `has_clock` quand vrais).

- [ ] **Step 1: Ajouter les tests**

```ruby
it "n'inscrit plus le format hérité {123} dans formule_deps" do
  tdc.formule_expression = '{123} + 1'
  tdc.valid?
  expect(tdc.formule_deps['champs']).to eq([])
end

it 'inscrit le bloc, pas le sous-champ, pour un agrégat' do
  tdc.formule_expression = "SOMME({tdc#{bloc.stable_id}/sub_#{sub.stable_id}})"
  tdc.valid?
  expect(tdc.formule_deps['champs']).to eq([bloc.stable_id])
end
```

Les tests existants de cycle, de référence vers l'avant, de drapeaux et d'inférence de type servent de non-régression : ne pas les modifier, sauf ceux qui vérifient explicitement que `{123}` entre dans `formule_deps['champs']` (à remplacer par le premier test ci-dessus).

- [ ] **Step 2: Lancer, constater l'échec du premier test**

Run: `bundle exec rspec spec/models/types_de_champ/formule_type_de_champ_spec.rb`
Expected: FAIL sur « n'inscrit plus le format hérité » (`[123]` au lieu de `[]`)

- [ ] **Step 3: Modifier `FormuleTypeDeChamp`**

- `circular_reference?` : garde ses deux gardes (`stable_id` nil, révision nil), puis `revision.formula_graph.circular_reference?(@type_de_champ.stable_id, @type_de_champ.formule_expression)`.
- `forward_reference?` : mêmes gardes, puis `revision.formula_graph.forward_reference?(…)`.
- `compute_formule_deps_from_expression` : `deps['champs'] = FormulaReferences.stable_ids(expression)`. Supprimer `FORMULE_DEPS_TDC_PATTERN`, `FORMULE_DEPS_LEGACY_PATTERN` et `extract_dependent_stable_ids`.
- `validate_expression` : le contrôle des références trop courtes et la construction de `testable` passent par `FormulaReferences` (`scan` et `gsub`). Attention : le contrôle « référence de moins de 3 caractères » porte aujourd'hui sur le texte accolades comprises, y compris `{}` que `PATTERN` ne capture pas ; garder pour ce seul contrôle l'expression `/\{[^}]*\}/` si `FormulaReferences` ne voit pas `{}`.
- `find_referenced_tdc` : ne garde que la forme `tdcN` (retirer la branche `{123}`).

Le graphe est construit sur `@type_de_champ.revisions.last`, comme aujourd'hui, et reçoit l'expression en cours de validation en argument : il ne doit pas lire celle du type de champ en mémoire de la révision.

- [ ] **Step 4: Lancer, constater le succès**

Run: `bundle exec rspec spec/models/types_de_champ/formule_type_de_champ_spec.rb spec/controllers/administrateurs/types_de_champ_controller_spec.rb spec/graphql/mutations`
Expected: PASS

- [ ] **Step 5: Commit** — `refactor(formule): cycle et référence vers l'avant validés par le graphe`

---

### Task 6: scénarios système et documentation

**Files:**
- Create: `spec/system/users/formula_graph_order_spec.rb`
- Modify: `CLAUDE.md` (section « Cascade des formules »), `french_polynesia.md` si le champ formule y décrit le graphe

**Interfaces:**
- Consumes: tout ce qui précède, à travers l'interface.

- [ ] **Step 1: Écrire deux scénarios**, sur le modèle de `spec/system/users/formula_repetition_root_source_spec.rb` (mise en place, connexion, attente de l'enregistrement automatique).

Scénario 1 — « une formule-ligne en tête de bloc suit une formule racine » : démarche du cas 2 de la tâche 4 ; l'usager, sur un dossier en brouillon, saisit `Coef = 1` puis `Coef = 3` ; la page affiche `Taux = 6` et, dans la ligne, `Montant = 60`, sans rechargement.

Scénario 2 — « une annotation privée en tête suit une formule publique » : démarche du cas 1 de la tâche 4 ; l'usager saisit `Source = 5` puis `Source = 10` sur son brouillon et dépose le dossier ; un instructeur de la démarche ouvre l'onglet des annotations privées et lit `Plus un = 21`.

- [ ] **Step 2: Lancer**

Run: `NO_HEADLESS= bundle exec rspec spec/system/users/formula_graph_order_spec.rb spec/system/users/formula_repetition_root_source_spec.rb spec/system/users/formula_cascade_spec.rb`
Expected: PASS

- [ ] **Step 3: Mettre à jour `CLAUDE.md`**

Dans « Cascade des formules », ajouter un paragraphe de cinq lignes au plus : le graphe (`revision.formula_graph`) est la seule source de l'ordre de calcul et des dépendants ; toute nouvelle analyse de `{…}` passe par `FormulaReferences` ; les recalculs par drapeau incluent l'aval. Ne pas réécrire le reste de la section.

- [ ] **Step 4: Vérifications finales**

Run: `bundle exec rubocop app/services/formula_references.rb app/services/formula_reference_scope.rb app/services/formula_dependency_graph.rb app/models/concerns/dossier_formula_refresh_concern.rb app/models/types_de_champ/formule_type_de_champ.rb app/models/champ.rb app/models/procedure_revision.rb app/models/procedure_revision_type_de_champ.rb app/controllers/concerns/turbo_champs_concern.rb`
Expected: aucune offense

Run: `git diff devpf --stat -- app/models/champ.rb app/models/procedure_revision.rb app/models/procedure_revision_type_de_champ.rb app/controllers/concerns/turbo_champs_concern.rb`
Expected: ces quatre fichiers upstream perdent des lignes ; les seules lignes ajoutées sont les accroches taguées `# pf:` (une dans `procedure_revision.rb`, trois délégations sous un commentaire dans `procedure_revision_type_de_champ.rb`, une modifiée dans `turbo_champs_concern.rb`).

- [ ] **Step 5: Commit, pousser, ouvrir la PR**

Commit : `test(formule): scénarios système de l'ordre de calcul entre niveaux`. PR vers `devpf` ; la description liste les deux corrections de comportement (ordre entre niveaux, aval des formules à drapeau), rappelle qu'aucune valeur déjà enregistrée n'est rattrapée (décision du 2026-11-27) et signale tout cas D1 qui passait déjà avant la modification. La suite complète est validée par la CI de la PR.
