# Plan A — Mutations GraphQL de construction de structure (champs) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exposer dans l'API GraphQL v2 de mes-demarches quatre mutations permettant d'ajouter, modifier, déplacer et supprimer un type de champ sur la révision **brouillon** d'une démarche, pour qu'un serveur MCP (plan séparé) pilote la construction de formulaire via Claude.

**Architecture :** Une classe de base PF `Mutations::DemarcheChampMutation` (héritant de `Mutations::BaseMutation`) factorise l'argument `demarche`, le format de retour et la résolution+autorisation de la procédure. Quatre mutations en héritent. Toutes opèrent sur `procedure.draft_revision` via les méthodes existantes (`add_type_de_champ`, `coordinate_and_tdc`, `find_and_ensure_exclusive_use`, `move_type_de_champ_after`, `remove_type_de_champ`). Le `write_access` du token est déjà imposé par `BaseMutation#ready?`. **Aucun fichier upstream n'est modifié sauf l'ajout de 4 lignes `# pf:` dans `mutation_type.rb`** (déjà la convention pour les mutations PF).

**Tech Stack :** Ruby 3.3, Rails 7.0, graphql-ruby, RSpec (`type: :graphql`).

**Périmètre / hors périmètre :**
- ✅ CRUD structurel : type_champ, libellé, description, obligatoire, parent (répétition/bloc), position, suppression.
- ❌ Configuration des options par type (valeurs de listes déroulantes, binding référentiel) → increment suivant.
- ❌ Logique conditionnelle (`demarcheDefinirCondition`) → Plan B.
- ❌ Description dynamique des types/référentiels → Plan C.
- ❌ Serveur MCP TypeScript → Plan D (consomme le schéma produit ici).

**Branche :** `feature/mcp-construction-formulaires` (déjà créée, courante).

**Garde-fou changement de type (cf. spec §7) :** `demarcheModifierChamp` **réutilise** (sans la refactorer ni la déplacer) la constante publique `TypesDeChampEditor::ChampComponent::ACCEPTED_TYPES` (dérivée de `Columns::ChampColumn::CAST`) + les garde-fous `coordinate.used_by_routing_rules?` / `used_by_ineligibilite_rules?`. Comportement identique à l'éditeur web : champ en brouillon seul → tout type ; champ publié → uniquement `[type_publié] + ACCEPTED_TYPES[type_publié]`. Aucun code upstream n'est modifié (on référence une constante publique existante).

---

## File Structure

- Create: `app/graphql/mutations/demarche_champ_mutation.rb` — classe de base PF (argument `demarche`, champs de retour, helper d'autorisation).
- Create: `app/graphql/mutations/demarche_ajouter_champ.rb` — mutation `demarcheAjouterChamp`.
- Create: `app/graphql/mutations/demarche_modifier_champ.rb` — mutation `demarcheModifierChamp`.
- Create: `app/graphql/mutations/demarche_deplacer_champ.rb` — mutation `demarcheDeplacerChamp`.
- Create: `app/graphql/mutations/demarche_supprimer_champ.rb` — mutation `demarcheSupprimerChamp`.
- Modify: `app/graphql/types/mutation_type.rb` — enregistrer les 4 mutations (section `# pf:`).
- Create: `spec/graphql/mutations/demarche_champ_mutations_spec.rb` — specs des 4 mutations.
- Modify (régénéré): `app/graphql/schema.graphql`, `app/graphql/schema.json`.

**Référence de patterns existants :** `app/graphql/mutations/demarche_cloner.rb` (résolution démarche + autorisation), `app/graphql/mutations/dossier_modifier_annotation_text.rb` (mutation enfant d'une base), `spec/graphql/annotation_spec.rb` (forme d'une spec `type: :graphql`).

---

## Task 1 : Classe de base + `demarcheAjouterChamp`

**Files:**
- Create: `app/graphql/mutations/demarche_champ_mutation.rb`
- Create: `app/graphql/mutations/demarche_ajouter_champ.rb`
- Modify: `app/graphql/types/mutation_type.rb`
- Test: `spec/graphql/mutations/demarche_champ_mutations_spec.rb`

- [ ] **Step 1 : Écrire le test qui échoue**

Créer `spec/graphql/mutations/demarche_champ_mutations_spec.rb` :

```ruby
# frozen_string_literal: true

RSpec.describe 'Mutations MCP construction de champs', type: :graphql do
  let(:admin) { create(:administrateur) }
  let(:procedure) { create(:procedure, administrateurs: [admin], types_de_champ_public: [{ type: :text, libelle: 'Nom' }]) }
  let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: true } }
  let(:variables) { {} }

  subject { API::V2::Schema.execute(query, variables:, context:) }

  let(:data) { subject['data'].deep_symbolize_keys }

  describe 'demarcheAjouterChamp' do
    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheAjouterChampInput!) {
        demarcheAjouterChamp(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end
    let(:variables) do
      { input: { demarche: { number: procedure.id }, typeChamp: 'email', libelle: 'Courriel' } }
    end

    it 'ajoute le champ au brouillon' do
      expect(data[:demarcheAjouterChamp][:errors]).to be_nil
      expect(data[:demarcheAjouterChamp][:champStableId]).to be_present
      libelles = procedure.draft_revision.reload.types_de_champ.map(&:libelle)
      expect(libelles).to include('Courriel')
    end

    context 'type inconnu' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, typeChamp: 'pas_un_type', libelle: 'X' } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheAjouterChamp][:champStableId]).to be_nil
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include('Type de champ inconnu')
      end
    end

    context 'démarche non autorisée pour le token' do
      let(:other_procedure) { create(:procedure) }
      let(:variables) do
        { input: { demarche: { number: other_procedure.id }, typeChamp: 'text', libelle: 'X' } }
      end

      it 'retourne une erreur d autorisation' do
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include('accès')
      end
    end

    context 'token en lecture seule' do
      let(:context) { { administrateur_id: admin.id, procedure_ids: admin.procedure_ids, write_access: false } }

      it 'refuse la mutation' do
        expect(data[:demarcheAjouterChamp][:errors].first[:message]).to include('lecture')
      end
    end
  end
end
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e demarcheAjouterChamp`
Expected: FAIL — `DemarcheAjouterChampInput` n'existe pas dans le schéma (erreur GraphQL « not defined » / mutation absente).

- [ ] **Step 3 : Créer la classe de base**

Créer `app/graphql/mutations/demarche_champ_mutation.rb` :

```ruby
# frozen_string_literal: true

# pf: classe de base des mutations MCP de construction de structure de démarche.
# Factorise l'argument `demarche`, le format de retour, et la résolution + autorisation
# de la procédure. Le contrôle `write_access` du token est assuré par BaseMutation#ready?.
module Mutations
  class DemarcheChampMutation < Mutations::BaseMutation
    argument :demarche, Types::DemarcheDescriptorType::FindDemarcheInput, "La démarche cible.", required: true

    field :champ_stable_id, String, "Le stable_id du champ concerné.", null: true
    field :errors, [Types::ValidationErrorType], null: true

    private

    # Retourne [procedure, nil] si autorisée, sinon [nil, "message d'erreur"].
    def find_authorized_procedure(demarche)
      number = demarche.number.presence || ApplicationRecord.id_from_typed_id(demarche.id)
      procedure = Procedure.find_by(id: number)

      return [nil, "La démarche \"#{number}\" n'existe pas."] if procedure.nil?
      return [nil, "Vous n'avez pas accès à la démarche \"#{number}\"."] unless context.authorized_demarche?(procedure)

      [procedure, nil]
    end
  end
end
```

- [ ] **Step 4 : Créer la mutation `demarcheAjouterChamp`**

Créer `app/graphql/mutations/demarche_ajouter_champ.rb` :

```ruby
# frozen_string_literal: true

# pf: ajoute un type de champ à la révision brouillon d'une démarche (construction MCP).
module Mutations
  class DemarcheAjouterChamp < Mutations::DemarcheChampMutation
    description "Ajouter un champ à la révision brouillon d'une démarche."

    argument :type_champ, String, "Type du champ (ex: text, email, integer_number, header_section, repetition…).", required: true
    argument :libelle, String, "Libellé du champ.", required: true
    argument :description, String, required: false
    argument :obligatoire, Boolean, required: false, default_value: false
    argument :prive, Boolean, "Annotation privée (instructeur) plutôt que champ usager.", required: false, default_value: false
    argument :parent_stable_id, String, "Pour insérer dans une répétition/bloc.", required: false
    argument :apres_stable_id, String, "Insérer juste après ce champ (sinon en tête).", required: false

    def resolve(demarche:, type_champ:, libelle:, description: nil, obligatoire: false, prive: false, parent_stable_id: nil, apres_stable_id: nil)
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      return { errors: ["Type de champ inconnu : \"#{type_champ}\"."] } unless TypeDeChamp.type_champs.key?(type_champ)

      params = { type_champ:, libelle:, description:, mandatory: obligatoire, private: prive }
      params[:parent_stable_id] = parent_stable_id if parent_stable_id.present?
      params[:after_stable_id] = apres_stable_id if apres_stable_id.present?

      type_de_champ = procedure.draft_revision.add_type_de_champ(params)

      if type_de_champ.valid?
        { champ_stable_id: type_de_champ.stable_id.to_s }
      else
        { errors: type_de_champ.errors.full_messages }
      end
    end
  end
end
```

- [ ] **Step 5 : Enregistrer la mutation**

Modifier `app/graphql/types/mutation_type.rb`. Juste avant la ligne `field :demarche_cloner, mutation: Mutations::DemarcheCloner`, ajouter :

```ruby
    # pf: mutations MCP — construction de la structure d'une démarche (brouillon)
    field :demarche_ajouter_champ, mutation: Mutations::DemarcheAjouterChamp
```

- [ ] **Step 6 : Lancer le test pour vérifier qu'il passe**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e demarcheAjouterChamp`
Expected: PASS (4 exemples verts).

- [ ] **Step 7 : Commit**

```bash
git add app/graphql/mutations/demarche_champ_mutation.rb \
        app/graphql/mutations/demarche_ajouter_champ.rb \
        app/graphql/types/mutation_type.rb \
        spec/graphql/mutations/demarche_champ_mutations_spec.rb
git commit -m "feat(graphql): mutation demarcheAjouterChamp + base DemarcheChampMutation"
```

---

## Task 2 : `demarcheModifierChamp`

**Files:**
- Create: `app/graphql/mutations/demarche_modifier_champ.rb`
- Modify: `app/graphql/types/mutation_type.rb`
- Test: `spec/graphql/mutations/demarche_champ_mutations_spec.rb` (ajouter un `describe`)

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter dans `spec/graphql/mutations/demarche_champ_mutations_spec.rb`, à l'intérieur du `RSpec.describe` racine :

```ruby
  describe 'demarcheModifierChamp' do
    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheModifierChampInput!) {
        demarcheModifierChamp(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end
    let(:stable_id) { procedure.draft_revision.types_de_champ.first.stable_id }

    context 'modification du libellé' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s, libelle: 'Nom complet' } }
      end

      it 'met à jour le libellé' do
        expect(data[:demarcheModifierChamp][:errors]).to be_nil
        expect(procedure.draft_revision.reload.types_de_champ.first.libelle).to eq('Nom complet')
      end
    end

    context 'changement de type INCOMPATIBLE sur un champ déjà publié' do
      let(:procedure) { create(:procedure, :published, administrateurs: [admin], types_de_champ_public: [{ type: :text, libelle: 'Nom' }]) }
      let(:variables) do
        # text -> integer_number n'est PAS dans ACCEPTED_TYPES[text] (incompatible migration)
        { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s, typeChamp: 'integer_number' } }
      end

      it 'est refusé' do
        expect(data[:demarcheModifierChamp][:champStableId]).to be_nil
        expect(data[:demarcheModifierChamp][:errors].first[:message]).to include('compatible')
      end
    end

    context 'changement de type COMPATIBLE sur un champ déjà publié' do
      let(:procedure) { create(:procedure, :published, administrateurs: [admin], types_de_champ_public: [{ type: :text, libelle: 'Nom' }]) }
      let(:variables) do
        # text -> textarea EST dans Columns::ChampColumn::CAST (morph compatible, comme l'éditeur web)
        { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s, typeChamp: 'textarea' } }
      end

      it 'est autorisé (réutilise ACCEPTED_TYPES)' do
        expect(data[:demarcheModifierChamp][:errors]).to be_nil
        expect(procedure.draft_revision.reload.types_de_champ.first.type_champ).to eq('textarea')
      end
    end

    context 'changement de type sur un champ seulement en brouillon' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s, typeChamp: 'integer_number' } }
      end

      it 'est autorisé (aucun dossier à migrer)' do
        expect(data[:demarcheModifierChamp][:errors]).to be_nil
        expect(procedure.draft_revision.reload.types_de_champ.first.type_champ).to eq('integer_number')
      end
    end
  end
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e demarcheModifierChamp`
Expected: FAIL — `DemarcheModifierChampInput` non défini.

- [ ] **Step 3 : Créer la mutation `demarcheModifierChamp`**

Créer `app/graphql/mutations/demarche_modifier_champ.rb` :

```ruby
# frozen_string_literal: true

# pf: modifie un champ existant de la révision brouillon (construction MCP).
module Mutations
  class DemarcheModifierChamp < Mutations::DemarcheChampMutation
    description "Modifier un champ existant de la révision brouillon d'une démarche."

    argument :stable_id, String, "stable_id du champ à modifier.", required: true
    argument :libelle, String, required: false
    argument :description, String, required: false
    argument :obligatoire, Boolean, required: false
    argument :type_champ, String, "Nouveau type. Interdit si le champ est déjà publié.", required: false

    def resolve(demarche:, stable_id:, libelle: nil, description: nil, obligatoire: nil, type_champ: nil)
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      draft = procedure.draft_revision
      coordinate, current_tdc = draft.coordinate_and_tdc(stable_id)
      return { errors: ["Le champ \"#{stable_id}\" n'existe pas dans cette démarche."] } if coordinate.nil?

      if type_champ.present? && type_champ != current_tdc.type_champ
        return { errors: ["Type de champ inconnu : \"#{type_champ}\"."] } unless TypeDeChamp.type_champs.key?(type_champ)

        # pf: on RÉUTILISE (sans la refactorer ni la déplacer) la logique de l'éditeur upstream
        # qui détermine les types cibles compatibles, via sa constante publique ACCEPTED_TYPES
        # (dérivée de Columns::ChampColumn::CAST) + les garde-fous routage/éligibilité de la
        # coordonnée. Si upstream fait évoluer la matrice, le MCP en bénéficie automatiquement.
        if coordinate.used_by_routing_rules? || coordinate.used_by_ineligibilite_rules?
          return { errors: ["Le type de ce champ n'est pas modifiable : il est utilisé par une règle de routage ou d'éligibilité."] }
        end

        published_type_champ = procedure.published_revision
          &.types_de_champ&.find { _1.stable_id.to_s == stable_id.to_s }&.type_champ

        if published_type_champ.present?
          accepted = [published_type_champ] + TypesDeChampEditor::ChampComponent::ACCEPTED_TYPES.fetch(published_type_champ, [])
          unless accepted.map(&:to_s).include?(type_champ.to_s)
            return { errors: ["Ce champ est déjà publié : son type ne peut être changé que vers un type compatible (#{accepted.join(', ')}), pour préserver les dossiers existants."] }
          end
        end
      end

      attrs = {}
      attrs[:libelle] = libelle unless libelle.nil?
      attrs[:description] = description unless description.nil?
      attrs[:mandatory] = obligatoire unless obligatoire.nil?
      attrs[:type_champ] = type_champ unless type_champ.nil?
      return { errors: ["Aucune modification fournie."] } if attrs.empty?

      type_de_champ = draft.find_and_ensure_exclusive_use(stable_id)

      if type_de_champ.update(attrs)
        { champ_stable_id: stable_id.to_s }
      else
        { errors: type_de_champ.errors.full_messages }
      end
    end
  end
end
```

- [ ] **Step 4 : Enregistrer la mutation**

Modifier `app/graphql/types/mutation_type.rb`, sous la ligne `field :demarche_ajouter_champ, …` :

```ruby
    field :demarche_modifier_champ, mutation: Mutations::DemarcheModifierChamp
```

- [ ] **Step 5 : Lancer le test pour vérifier qu'il passe**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e demarcheModifierChamp`
Expected: PASS (3 exemples verts).

- [ ] **Step 6 : Commit**

```bash
git add app/graphql/mutations/demarche_modifier_champ.rb \
        app/graphql/types/mutation_type.rb \
        spec/graphql/mutations/demarche_champ_mutations_spec.rb
git commit -m "feat(graphql): mutation demarcheModifierChamp (garde-fou type sur champ publié)"
```

---

## Task 3 : `demarcheDeplacerChamp`

**Files:**
- Create: `app/graphql/mutations/demarche_deplacer_champ.rb`
- Modify: `app/graphql/types/mutation_type.rb`
- Test: `spec/graphql/mutations/demarche_champ_mutations_spec.rb` (ajouter un `describe`)

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter dans le spec, dans le `RSpec.describe` racine. On part d'une procédure à deux champs :

```ruby
  describe 'demarcheDeplacerChamp' do
    let(:procedure) do
      create(:procedure, administrateurs: [admin], types_de_champ_public: [
        { type: :text, libelle: 'Premier' },
        { type: :text, libelle: 'Second' },
      ])
    end
    let(:premier) { procedure.draft_revision.types_de_champ.first }
    let(:second) { procedure.draft_revision.types_de_champ.second }

    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheDeplacerChampInput!) {
        demarcheDeplacerChamp(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end
    let(:variables) do
      { input: { demarche: { number: procedure.id }, stableId: premier.stable_id.to_s, apresStableId: second.stable_id.to_s } }
    end

    it 'place le premier champ après le second' do
      expect(data[:demarcheDeplacerChamp][:errors]).to be_nil
      libelles = procedure.draft_revision.reload.types_de_champ.map(&:libelle)
      expect(libelles).to eq(['Second', 'Premier'])
    end

    context 'champ de destination inexistant' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: premier.stable_id.to_s, apresStableId: '999999' } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheDeplacerChamp][:errors].first[:message]).to include('destination')
      end
    end
  end
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e demarcheDeplacerChamp`
Expected: FAIL — `DemarcheDeplacerChampInput` non défini.

- [ ] **Step 3 : Créer la mutation `demarcheDeplacerChamp`**

Créer `app/graphql/mutations/demarche_deplacer_champ.rb` :

```ruby
# frozen_string_literal: true

# pf: déplace un champ de la révision brouillon juste après un autre champ (construction MCP).
module Mutations
  class DemarcheDeplacerChamp < Mutations::DemarcheChampMutation
    description "Déplacer un champ de la révision brouillon juste après un autre champ."

    argument :stable_id, String, "stable_id du champ à déplacer.", required: true
    argument :apres_stable_id, String, "stable_id du champ après lequel placer le champ déplacé.", required: true

    def resolve(demarche:, stable_id:, apres_stable_id:)
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      draft = procedure.draft_revision

      source_coordinate, _ = draft.coordinate_and_tdc(stable_id)
      return { errors: ["Le champ \"#{stable_id}\" n'existe pas dans cette démarche."] } if source_coordinate.nil?

      target_coordinate, _ = draft.coordinate_and_tdc(apres_stable_id)
      return { errors: ["Le champ de destination \"#{apres_stable_id}\" n'existe pas."] } if target_coordinate.nil?

      draft.move_type_de_champ_after(stable_id, target_coordinate.position)
      { champ_stable_id: stable_id.to_s }
    end
  end
end
```

- [ ] **Step 4 : Enregistrer la mutation**

Modifier `app/graphql/types/mutation_type.rb`, sous la ligne `field :demarche_modifier_champ, …` :

```ruby
    field :demarche_deplacer_champ, mutation: Mutations::DemarcheDeplacerChamp
```

- [ ] **Step 5 : Lancer le test pour vérifier qu'il passe**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e demarcheDeplacerChamp`
Expected: PASS (2 exemples verts).

- [ ] **Step 6 : Commit**

```bash
git add app/graphql/mutations/demarche_deplacer_champ.rb \
        app/graphql/types/mutation_type.rb \
        spec/graphql/mutations/demarche_champ_mutations_spec.rb
git commit -m "feat(graphql): mutation demarcheDeplacerChamp"
```

---

## Task 4 : `demarcheSupprimerChamp`

**Files:**
- Create: `app/graphql/mutations/demarche_supprimer_champ.rb`
- Modify: `app/graphql/types/mutation_type.rb`
- Test: `spec/graphql/mutations/demarche_champ_mutations_spec.rb` (ajouter un `describe`)

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter dans le spec, dans le `RSpec.describe` racine :

```ruby
  describe 'demarcheSupprimerChamp' do
    let(:stable_id) { procedure.draft_revision.types_de_champ.first.stable_id }
    let(:query) do
      <<-GRAPHQL
      mutation($input: DemarcheSupprimerChampInput!) {
        demarcheSupprimerChamp(input: $input) {
          champStableId
          errors { message }
        }
      }
      GRAPHQL
    end
    let(:variables) do
      { input: { demarche: { number: procedure.id }, stableId: stable_id.to_s } }
    end

    it 'supprime le champ du brouillon' do
      expect(data[:demarcheSupprimerChamp][:errors]).to be_nil
      expect(procedure.draft_revision.reload.types_de_champ).to be_empty
    end

    context 'champ inexistant' do
      let(:variables) do
        { input: { demarche: { number: procedure.id }, stableId: '999999' } }
      end

      it 'retourne une erreur' do
        expect(data[:demarcheSupprimerChamp][:errors].first[:message]).to include("n'existe pas")
      end
    end
  end
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e demarcheSupprimerChamp`
Expected: FAIL — `DemarcheSupprimerChampInput` non défini.

- [ ] **Step 3 : Créer la mutation `demarcheSupprimerChamp`**

Créer `app/graphql/mutations/demarche_supprimer_champ.rb` :

```ruby
# frozen_string_literal: true

# pf: supprime un champ de la révision brouillon (construction MCP).
module Mutations
  class DemarcheSupprimerChamp < Mutations::DemarcheChampMutation
    description "Supprimer un champ de la révision brouillon d'une démarche."

    argument :stable_id, String, "stable_id du champ à supprimer.", required: true

    def resolve(demarche:, stable_id:)
      procedure, error = find_authorized_procedure(demarche)
      return { errors: [error] } if error

      coordinate = procedure.draft_revision.remove_type_de_champ(stable_id)

      if coordinate.nil?
        { errors: ["Le champ \"#{stable_id}\" n'existe pas dans cette démarche."] }
      else
        { champ_stable_id: stable_id.to_s }
      end
    end
  end
end
```

- [ ] **Step 4 : Enregistrer la mutation**

Modifier `app/graphql/types/mutation_type.rb`, sous la ligne `field :demarche_deplacer_champ, …` :

```ruby
    field :demarche_supprimer_champ, mutation: Mutations::DemarcheSupprimerChamp
```

- [ ] **Step 5 : Lancer le test pour vérifier qu'il passe**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb -e demarcheSupprimerChamp`
Expected: PASS (2 exemples verts).

- [ ] **Step 6 : Commit**

```bash
git add app/graphql/mutations/demarche_supprimer_champ.rb \
        app/graphql/types/mutation_type.rb \
        spec/graphql/mutations/demarche_champ_mutations_spec.rb
git commit -m "feat(graphql): mutation demarcheSupprimerChamp"
```

---

## Task 5 : Régénérer le schéma GraphQL

**Files:**
- Modify (régénéré): `app/graphql/schema.graphql`, `app/graphql/schema.json`

- [ ] **Step 1 : Vérifier que toute la suite passe**

Run: `bundle exec rspec spec/graphql/mutations/demarche_champ_mutations_spec.rb`
Expected: PASS (tous les exemples des tâches 1–4 verts).

- [ ] **Step 2 : Régénérer le schéma**

Run: `bin/rails graphql:schema:dump`
Expected: met à jour `app/graphql/schema.graphql` et `app/graphql/schema.json` avec les 4 nouvelles mutations (`demarcheAjouterChamp`, `demarcheModifierChamp`, `demarcheDeplacerChamp`, `demarcheSupprimerChamp`) et leurs types d'input.

- [ ] **Step 3 : Vérifier la présence des mutations dans le SDL**

Run: `grep -E "demarcheAjouterChamp|demarcheModifierChamp|demarcheDeplacerChamp|demarcheSupprimerChamp" app/graphql/schema.graphql`
Expected: les 4 noms apparaissent.

- [ ] **Step 4 : Lint**

Run: `bundle exec rubocop app/graphql/mutations/demarche_champ_mutation.rb app/graphql/mutations/demarche_ajouter_champ.rb app/graphql/mutations/demarche_modifier_champ.rb app/graphql/mutations/demarche_deplacer_champ.rb app/graphql/mutations/demarche_supprimer_champ.rb`
Expected: no offenses (corriger avec `-A` si besoin).

- [ ] **Step 5 : Commit**

```bash
git add app/graphql/schema.graphql app/graphql/schema.json
git commit -m "chore(graphql): dump schéma avec les mutations de construction de champs"
```

---

## Self-Review (effectuée à l'écriture)

- **Couverture spec (périmètre Plan A) :** les 4 mutations structurelles (ajouter/modifier/déplacer/supprimer) sont chacune couvertes par une tâche TDD + specs (happy path + erreurs). Le garde-fou de type sur champ publié (spec §7) est testé en Task 2. L'enregistrement + dump du schéma est en Task 5. Conditions (§5), description référentiels (§6) et serveur MCP (§4) sont **explicitement hors de ce plan** (plans B/C/D) — ce n'est pas une lacune mais un découpage.
- **Placeholders :** aucun. Tout le code et les commandes sont concrets.
- **Cohérence des types :** `DemarcheChampMutation` (base) expose `champ_stable_id` + `errors` ; les 4 mutations retournent exactement `{ champ_stable_id: }` ou `{ errors: [...] }`. Les noms GraphQL camelisés utilisés dans les specs (`champStableId`, `typeChamp`, `stableId`, `apresStableId`, `parentStableId`, `obligatoire`, `prive`) correspondent aux `argument`/`field` snake_case. `find_authorized_procedure` est défini dans la base et appelé identiquement partout.

---

## Roadmap (plans suivants — à générer après Plan A vert)

| Plan | Sujet | Dépend de | Notes d'investigation préalable |
|---|---|---|---|
| **B** | `demarcheDefinirCondition` (logique 1 niveau ET/OU) | A | Tracer `Logic::Constant#type` et la coercition de `valeur` selon le type du champ source ; valider via `Logic.compatible_type?`. |
| **C** | Query PF de description (types + référentiels + colonnes) | A | Clarifier le modèle des référentiels PF (créés par champ, pas de catalogue global ni de scoping admin) avant d'exposer une liste. |
| **D** | Serveur MCP TypeScript (`../mcp-mes-demarches`) | A (schéma dumpé) | Outils `ajouter/modifier/deplacer/supprimer_champ` + `lire_demarche`. `type_modifiable` dérivé côté client en comparant le stable_id à la révision publiée (données déjà exposées par la query `demarche`) → zéro champ backend supplémentaire. |
| **Increment** | Configuration des options (valeurs de listes déroulantes, binding référentiel) | A, C | Étendre `demarcheModifierChamp` ou nouvelle mutation dédiée. |
