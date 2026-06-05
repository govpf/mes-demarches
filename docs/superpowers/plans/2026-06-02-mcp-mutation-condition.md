# Plan B — Mutation `demarcheDefinirCondition` (logique conditionnelle) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter la mutation GraphQL `demarcheDefinirCondition` qui pose (ou retire) la condition d'affichage d'un champ de la révision brouillon, à partir d'une liste simplifiée de termes (`champ source / opérateur / valeur`) combinés par ET ou OU à un seul niveau.

**Architecture :** La mutation hérite de la base `Mutations::DemarcheChampMutation` (Plan A). Elle construit l'arbre `Logic` **directement** via les constructeurs de classe (`Logic::ChampValue.new`, `Logic::Constant.new`, `Logic::And.new`/`Logic::Or.new`, `Logic.class_from_name(...).new`), réutilise le validateur intégré `condition.errors(source_tdcs)` du modèle Logic (qui couvre compatibilité de type, appartenance aux options enum, opérateurs numériques), puis assigne via `tdc.update!(condition:)`. **Aucun fichier upstream modifié** sauf l'ajout d'une ligne `# pf:` dans `mutation_type.rb`.

**Tech Stack :** Ruby 3.3, Rails 7.0, graphql-ruby, modèle `Logic` (sérialisé via `LogicSerializer`), RSpec (`type: :graphql`).

**Pré-requis :** Plan A mergé/présent sur la branche `feature/mcp-construction-formulaires` (base `Mutations::DemarcheChampMutation`, `find_authorized_procedure`, `champ_stable_id`/`errors` fields).

---

## Décisions d'architecture (pourquoi pas ConditionForm)

`ConditionForm` (`app/models/condition_form.rb`) est l'adaptateur du **formulaire HTML** : ses `rows` attendent `targeted_champ` en JSON et les booléens pré-sérialisés en termes JSON. La mutation est un **autre** adaptateur (GraphQL → Logic) ; elle vise donc le **modèle `Logic` directement**, ce qui est la vraie réutilisation (modèle + validateur), sans dépendre du format de fil HTML de `ConditionForm`.

Points clés vérifiés dans le code :
- **Source = champs en amont uniquement.** Le controller utilise `coordinate.upper_coordinates.map(&:type_de_champ)` comme `source_tdcs`. Une condition ne référence que des champs situés AVANT la cible (et dans le même scope public/privé). La mutation fait pareil.
- **Aucune validation de compatibilité côté controller/modèle** (l'UI ne propose que des opérateurs compatibles). La mutation DOIT valider, car Claude peut envoyer un opérateur/valeur incompatible. On réutilise `condition.errors(source_tdcs)` (chaque opérateur Logic a sa propre méthode `errors` : `Eq#errors` appelle `compatible_type?` + vérifie l'appartenance aux options enum ; `BinaryOperator#errors` exige `:number` pour `>`,`<`… ; `IncludeOperator#errors` pour les choix multiples).
- **Coercition de la valeur** : `ConditionForm#parse_value` fait number→Float/Int, booléen→bool, sinon string. On reproduit cette logique en ~6 lignes dans un helper privé `coerce_constant` (format d'entrée différent ; cross-référencer `ConditionForm#parse_value`). Les constantes enum restent des **strings** (c'est volontaire : `compatible_type?` accepte `[:enum, :string]`).
- `Logic.class_from_name(name)` et `Logic.compatible_type?` sont publics (`self.`). Les helpers `ds_and`/`champ_value`/`constant` sont des méthodes d'instance (mixin) → on utilise les **constructeurs de classe** à la place.

**Opérateurs exposés (friendly → classe Logic, toutes présentes dans `Logic.class_from_name`) :**

| `operateur` (API) | Classe Logic | Type de champ source typique |
|---|---|---|
| `egal` | `Logic::Eq` | tout (texte, enum, booléen, nombre) |
| `different` | `Logic::NotEq` | enum |
| `superieur` | `Logic::GreaterThan` | nombre |
| `superieur_ou_egal` | `Logic::GreaterThanEq` | nombre |
| `inferieur` | `Logic::LessThan` | nombre |
| `inferieur_ou_egal` | `Logic::LessThanEq` | nombre |
| `inclut` | `Logic::IncludeOperator` | choix multiple (`:enums`) |
| `exclut` | `Logic::ExcludeOperator` | choix multiple |
| `dans_archipel` | `Logic::InArchipelOperator` | commune/code postal PF |
| `hors_archipel` | `Logic::NotInArchipelOperator` | commune/code postal PF |
| `dans_departement` | `Logic::InDepartementOperator` | commune/adresse |
| `dans_region` | `Logic::InRegionOperator` | commune/département |

---

## File Structure

- Create: `app/graphql/types/condition_terme_input.rb` — input object `Types::ConditionTermeInput` (champSourceStableId, operateur, valeur).
- Create: `app/graphql/mutations/demarche_definir_condition.rb` — mutation `Mutations::DemarcheDefinirCondition`.
- Modify: `app/graphql/types/mutation_type.rb` — enregistrer la mutation (sous le groupe `# pf:`).
- Modify: `spec/graphql/mutations/demarche_champ_mutations_spec.rb` — ajouter un `describe`.
- Modify (régénéré): `app/graphql/schema.graphql`, `app/graphql/schema.json`.

---

## Task 1 : input type + mutation `demarcheDefinirCondition`

**Files:**
- Create: `app/graphql/types/condition_terme_input.rb`
- Create: `app/graphql/mutations/demarche_definir_condition.rb`
- Modify: `app/graphql/types/mutation_type.rb`
- Test: `spec/graphql/mutations/demarche_champ_mutations_spec.rb`

- [ ] **Step 1 : Écrire les tests qui échouent**

Ajouter ce `describe` à l'intérieur du `RSpec.describe 'Mutations MCP construction de champs', type: :graphql do … end` (sibling des autres) :

```ruby
  describe 'demarcheDefinirCondition' do
    # Source en amont (premier champ) + cible (second champ) qui portera la condition.
    let(:procedure) do
      create(:procedure, administrateurs: [admin], types_de_champ_public: [
        { type: :integer_number, libelle: 'Âge' },
        { type: :text, libelle: 'Détail' },
      ])
    end
    let(:source) { procedure.draft_revision.types_de_champ.first }
    let(:cible)  { procedure.draft_revision.types_de_champ.second }

    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheDefinirConditionInput!) {
        demarcheDefinirCondition(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end

    def cible_condition
      procedure.draft_revision.reload.types_de_champ.find { _1.stable_id == cible.stable_id }.condition
    end

    context 'condition numérique simple' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s,
                   termes: [{ champSourceStableId: source.stable_id.to_s, operateur: 'superieur_ou_egal', valeur: '18' }] } }
      end

      it 'pose la condition' do
        expect(data[:demarcheDefinirCondition][:errors]).to be_nil
        expect(data[:demarcheDefinirCondition][:champStableId]).to eq(cible.stable_id.to_s)
        condition = cible_condition
        expect(condition).to be_a(Logic::GreaterThanEq)
        expect(condition.left).to be_a(Logic::ChampValue)
        expect(condition.left.stable_id).to eq(source.stable_id)
        expect(condition.right).to be_a(Logic::Constant)
        expect(condition.right.value).to eq(18)
      end
    end

    context 'combinateur OU avec deux termes' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s, combinateur: 'OU',
                   termes: [
                     { champSourceStableId: source.stable_id.to_s, operateur: 'superieur', valeur: '18' },
                     { champSourceStableId: source.stable_id.to_s, operateur: 'inferieur', valeur: '5' },
                   ] } }
      end

      it 'construit un Logic::Or à deux opérandes' do
        expect(data[:demarcheDefinirCondition][:errors]).to be_nil
        condition = cible_condition
        expect(condition).to be_a(Logic::Or)
        expect(condition.operands.size).to eq(2)
      end
    end

    context 'liste de termes vide' do
      before do
        # pose d'abord une condition, pour vérifier qu'on la retire
        cible.update!(condition: Logic::GreaterThanEq.new(Logic::ChampValue.new(source.stable_id), Logic::Constant.new(1)))
      end
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s, termes: [] } }
      end

      it 'retire la condition' do
        expect(data[:demarcheDefinirCondition][:errors]).to be_nil
        expect(cible_condition).to be_nil
      end
    end

    context 'opérateur inconnu' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s,
                   termes: [{ champSourceStableId: source.stable_id.to_s, operateur: 'entre', valeur: '18' }] } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheDefinirCondition][:champStableId]).to be_nil
        expect(data[:demarcheDefinirCondition][:errors].first[:message]).to include('Opérateur inconnu')
      end
    end

    context 'opérateur incompatible avec le type du champ source' do
      # 'superieur' sur un champ texte n'est pas valide (BinaryOperator#errors exige :number)
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s,
                   termes: [{ champSourceStableId: cible.stable_id.to_s, operateur: 'superieur', valeur: '3' }] } }
      end

      # NB: ici le champ source = la cible elle-même (texte), qui n'est de toute façon pas en amont :
      # la condition sera invalide. On vérifie qu'une erreur est remontée (pas un 500).
      it 'retourne une erreur (pas un 500)' do
        expect(data[:demarcheDefinirCondition][:champStableId]).to be_nil
        expect(data[:demarcheDefinirCondition][:errors]).to be_present
      end
    end

    context 'champ source non situé en amont' do
      # source = un champ qui vient APRÈS la cible → pas dans upper_coordinates → :unmanaged
      let(:procedure) do
        create(:procedure, administrateurs: [admin], types_de_champ_public: [
          { type: :text, libelle: 'Cible' },
          { type: :integer_number, libelle: 'AprèsSource' },
        ])
      end
      let(:cible)  { procedure.draft_revision.types_de_champ.first }
      let(:apres)  { procedure.draft_revision.types_de_champ.second }
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: cible.stable_id.to_s,
                   termes: [{ champSourceStableId: apres.stable_id.to_s, operateur: 'superieur', valeur: '1' }] } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheDefinirCondition][:champStableId]).to be_nil
        expect(data[:demarcheDefinirCondition][:errors]).to be_present
      end
    end
  end
```

- [ ] **Step 2 : Lancer, vérifier l'échec**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e demarcheDefinirCondition`
Expected: FAIL — `DemarcheDefinirConditionInput` non défini.

- [ ] **Step 3 : Créer l'input type**

Créer `app/graphql/types/condition_terme_input.rb` :

```ruby
# frozen_string_literal: true

# pf: un terme d'une condition d'affichage construite via le MCP.
module Types
  class ConditionTermeInput < Types::BaseInputObject
    description "Un terme d'une condition d'affichage : champ source + opérateur + valeur."

    argument :champ_source_stable_id, String, "stable_id du champ source (doit être situé AVANT le champ conditionné).", required: true
    argument :operateur, String, "egal | different | superieur | superieur_ou_egal | inferieur | inferieur_ou_egal | inclut | exclut | dans_archipel | hors_archipel | dans_departement | dans_region", required: true
    argument :valeur, String, "Valeur comparée. Pour un champ booléen : 'true'/'false'. Pour un nombre : '18'. Pour une liste : le libellé d'option.", required: true
  end
end
```

- [ ] **Step 4 : Créer la mutation**

Créer `app/graphql/mutations/demarche_definir_condition.rb` :

```ruby
# frozen_string_literal: true

# pf: pose ou retire la condition d'affichage d'un champ de la révision brouillon (construction MCP).
# Construit l'arbre Logic directement (constructeurs de classe) et réutilise le validateur
# intégré `condition.errors(source_tdcs)`. La source d'une condition est limitée aux champs
# situés en amont (upper_coordinates), comme dans l'éditeur.
module Mutations
  class DemarcheDefinirCondition < Mutations::DemarcheChampMutation
    description "Définir (ou retirer) la condition d'affichage d'un champ de la révision brouillon."

    OPERATEUR_TO_LOGIC = {
      'egal' => 'Logic::Eq',
      'different' => 'Logic::NotEq',
      'superieur' => 'Logic::GreaterThan',
      'superieur_ou_egal' => 'Logic::GreaterThanEq',
      'inferieur' => 'Logic::LessThan',
      'inferieur_ou_egal' => 'Logic::LessThanEq',
      'inclut' => 'Logic::IncludeOperator',
      'exclut' => 'Logic::ExcludeOperator',
      'dans_archipel' => 'Logic::InArchipelOperator',
      'hors_archipel' => 'Logic::NotInArchipelOperator',
      'dans_departement' => 'Logic::InDepartementOperator',
      'dans_region' => 'Logic::InRegionOperator'
    }.freeze

    argument :stable_id, String, "stable_id du champ dont on définit la condition d'affichage.", required: true
    argument :combinateur, String, "ET ou OU pour combiner plusieurs termes (défaut : ET).", required: false, default_value: 'ET'
    argument :termes, [Types::ConditionTermeInput], "Termes de la condition. Liste vide => retire la condition.", required: true

    def resolve(demarche:, stable_id:, termes:, combinateur: 'ET')
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      draft = procedure.draft_revision
      coordinate, _ = draft.coordinate_and_tdc(stable_id)
      return { errors: ["Le champ \"#{stable_id}\" n'existe pas dans cette démarche."] } if coordinate.nil?

      type_de_champ = draft.find_and_ensure_exclusive_use(stable_id)
      coordinate = draft.coordinate_for(type_de_champ)
      source_tdcs = coordinate.upper_coordinates.map(&:type_de_champ)

      if termes.empty?
        type_de_champ.update!(condition: nil)
        return { champ_stable_id: stable_id.to_s }
      end

      sub_conditions = []
      termes.each do |terme|
        operator_class_name = OPERATEUR_TO_LOGIC[terme.operateur]
        if operator_class_name.nil?
          return { errors: ["Opérateur inconnu : \"#{terme.operateur}\". Valeurs acceptées : #{OPERATEUR_TO_LOGIC.keys.join(', ')}."] }
        end

        left = Logic::ChampValue.new(terme.champ_source_stable_id.to_i)
        right = coerce_constant(left, terme.valeur, source_tdcs)
        sub_conditions << Logic.class_from_name(operator_class_name).new(left, right)
      end

      condition = if sub_conditions.one?
        sub_conditions.first
      elsif combinateur == 'OU'
        Logic::Or.new(sub_conditions)
      else
        Logic::And.new(sub_conditions)
      end

      condition_errors = condition.errors(source_tdcs)
      return { errors: condition_errors.map { humanize_condition_error(_1) } } if condition_errors.present?

      type_de_champ.update!(condition:)
      { champ_stable_id: stable_id.to_s }
    end

    private

    # pf: reproduit la coercition de ConditionForm#parse_value (format d'entrée différent).
    # number -> Integer/Float ; booléen -> true/false ; sinon string (les enums restent des
    # strings, compatible_type? accepte [:enum, :string]).
    def coerce_constant(left, valeur, source_tdcs)
      case left.type(source_tdcs)
      when :boolean
        Logic::Constant.new(ActiveModel::Type::Boolean.new.cast(valeur))
      when :number
        number = Float(valeur) rescue nil
        Logic::Constant.new(number.nil? ? valeur : (number % 1 == 0 ? number.to_i : number))
      else
        Logic::Constant.new(valeur)
      end
    end

    def humanize_condition_error(err)
      return err if err.is_a?(String)

      case err[:type]
      when :unmanaged
        "Le champ source (stable_id #{err[:stable_id]}) doit être un champ situé avant le champ conditionné."
      when :incompatible
        "La valeur n'est pas compatible avec le type du champ source (stable_id #{err[:stable_id]})."
      when :not_included
        "La valeur ne fait pas partie des options du champ source (stable_id #{err[:stable_id]})."
      when :empty_options
        "Le champ source (stable_id #{err[:stable_id]}) n'a pas d'options configurées."
      when :required_number
        "L'opérateur « #{err[:operator_name]} » requiert des nombres des deux côtés."
      when :required_include
        "Pour un champ à choix multiples, utilisez l'opérateur « inclut » ou « exclut »."
      else
        "Condition invalide (#{err[:type]})."
      end
    end
  end
end
```

- [ ] **Step 5 : Enregistrer la mutation**

Dans `app/graphql/types/mutation_type.rb`, sous `field :demarche_supprimer_champ, mutation: Mutations::DemarcheSupprimerChamp`, ajouter :

```ruby
    field :demarche_definir_condition, mutation: Mutations::DemarcheDefinirCondition
```

- [ ] **Step 6 : Lancer, vérifier que ça passe**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e demarcheDefinirCondition`
Expected: PASS (6 exemples). Si un test « incompatible/non amont » ne remonte PAS d'erreur (la condition est posée à tort), STOP et reporte : cela signifie que `condition.errors(source_tdcs)` ne couvre pas ce cas — il faudra ajouter une validation explicite (vérifier que chaque `champ_source_stable_id` ∈ `source_tdcs.map(&:stable_id)`). Ne pas affaiblir le test.

- [ ] **Step 7 : Rubocop + Commit**

`bundle exec rubocop app/graphql/mutations/demarche_definir_condition.rb app/graphql/types/condition_terme_input.rb`
```bash
git add app/graphql/mutations/demarche_definir_condition.rb app/graphql/types/condition_terme_input.rb app/graphql/types/mutation_type.rb spec/graphql/mutations/demarche_champ_mutations_spec.rb
git commit -m "feat(graphql): mutation demarcheDefinirCondition (réutilise le validateur Logic#errors)"
```

---

## Task 2 : Régénérer le schéma GraphQL

**Files:**
- Modify (régénéré): `app/graphql/schema.graphql`, `app/graphql/schema.json`

- [ ] **Step 1 : Vérifier toute la suite**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb`
Expected: tous verts (les exemples des Plans A + B). Si échec, STOP et reporte.

- [ ] **Step 2 : Régénérer**

Run: `bin/rails graphql:schema:dump`

- [ ] **Step 3 : Vérifier le SDL**

Run: `grep -E "demarcheDefinirCondition|ConditionTermeInput|DemarcheDefinirConditionInput" app/graphql/schema.graphql`
Expected: les trois apparaissent.

- [ ] **Step 4 : Confirmer que seuls les 2 fichiers de schéma changent et que le SDL est additif**

Run: `git status --short` (seuls `schema.graphql` et `schema.json` modifiés)
Run: `git diff --stat app/graphql/schema.graphql` puis vérifier qu'aucune ligne réelle de type/field préexistant n'est SUPPRIMÉE dans `schema.graphql` (diff purement additif). Résumer en une ligne ce que le diff ajoute. Si des suppressions réelles apparaissent dans le SDL, STOP et reporte.

- [ ] **Step 5 : Commit**

```bash
git add app/graphql/schema.graphql app/graphql/schema.json
git commit -m "chore(graphql): dump schéma avec demarcheDefinirCondition"
```

---

## Self-Review (effectuée à l'écriture)

- **Couverture spec :** condition numérique simple (structure de l'arbre vérifiée), combinateur OU à 2 termes, retrait (termes vides), opérateur inconnu, opérateur incompatible (pas de 500), champ source non amont. Le périmètre Plan B (logique conditionnelle 1 niveau ET/OU) est couvert.
- **Placeholders :** aucun. Tout le code est concret.
- **Cohérence des types :** la mutation hérite de `DemarcheChampMutation` (Plan A) et réutilise `find_authorized_procedure` + le format de retour `{ champ_stable_id: }`/`{ errors: }`. Les noms camelisés des specs (`champSourceStableId`, `operateur`, `valeur`, `stableId`, `combinateur`, `termes`) correspondent aux arguments snake_case. Constructeurs `Logic::*` et `Logic.class_from_name` confirmés présents et publics ; validation via `condition.errors(source_tdcs)` confirmée.

## Risque résiduel à surveiller

- Si `condition.errors(source_tdcs)` ne flagge pas un `champ_source` hors amont comme `:unmanaged` (cas du test « champ source non situé en amont »), ajouter une garde explicite : `return { errors: [...] } unless source_tdcs.map { _1.stable_id.to_s }.include?(terme.champ_source_stable_id.to_s)`. À confirmer par le test en Step 6.
- `humanize_condition_error` mappe les `:type` connus de `Logic::*#errors` ; un nouveau type d'erreur upstream tomberait dans le fallback générique (acceptable).
