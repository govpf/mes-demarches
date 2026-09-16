# Référentiel de Polynésie — Cascade : reprise après recette — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Intégrer à la PR #554 les quatre retours de recette du 2026-09-15 : message d'état vide orienté usager, déplacement de la configuration du filtre vers le panneau 3 du wizard « Configurer le champ », case « option autre » au standard DSFR, et libellés par défaut du mapping sans le préfixe `$.`.

**Architecture:** Le modèle (`referentiel_filter`, `ContextualFilter`, contrôleur de recherche, validations) ne change pas. Seule l'interface admin bouge : le bloc « Restreindre… » quitte la carte du champ (`TypesDeChampEditor::ChampComponent`) pour devenir une troisième section du panneau « préremplir et afficher » du wizard (`Referentiels::PrefillAndDisplayComponent`), enregistrée par `Administrateurs::ReferentielsController#update_prefill_and_display_type_de_champ` via le setter existant `TypeDeChamp#referentiel_filter_form=`. La carte du champ n'affiche plus qu'un rappel en lecture seule issu de la configuration stockée (zéro appel Baserow à l'affichage de l'éditeur).

**Tech Stack:** Rails 7 / Ruby 3.3, ViewComponent, HAML, Stimulus `hide-target`, RSpec, Capybara/Playwright headless.

**Spec:** `docs/superpowers/specs/2026-06-17-referentiel-polynesie-filtres-contextuels-design.md` (§1 à mettre à jour en Task 16). Décisions de recette : conversation du 2026-09-15 (règle de placement : « ce qui parle du formulaire reste dans le champ ; ce qui relie les colonnes Baserow au formulaire va dans Configurer le champ »).

## Global Constraints

- Branche `feature/referentiel-cascade`, extraite dans le dépôt principal `/home/clautier/Rubymine/mes-demarches` (plus de worktree). Ne pas pousser sans instruction du contrôleur.
- Aucun changement de modèle ni de sécurité : `ContextualFilter`, `#search`, `referentiel_filter_integrity`, `ReferentielFilterValidator` sont hors périmètre.
- Apostrophe typographique « ’ » (U+2019) dans tout texte fr d'interface et dans les expectations de specs.
- `# pf:` / `-# pf:` sur tout code spécifique PF ; fichiers partagés avec upstream (`mapping_form_component.rb`, `mapping_form_base.rb`, `prefill_and_display_component.html.haml`, `referentiels_controller.rb`) : modifications minimales et taguées.
- Specs système en headless uniquement : `NO_HEADLESS= bundle exec rspec …`.
- Commits en français, terminés par `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Lint : `bundle exec rubocop -a <fichiers>`, `bundle exec haml-lint <haml>`, `bundle exec i18n-tasks missing --locales fr`, `bundle exec i18n-tasks unused --locale en`.

---

### Task 12 : Message d'état vide orienté usager

**Files:**
- Modify: `config/locales/shared.fr.yml:59`, `config/locales/shared.en.yml:50`
- Modify: `app/lib/referentiel_de_polynesie/contextual_filter.rb` (`empty_label`)
- Test: `spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb` (describe `#empty_label`), `spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb`, `spec/system/users/referentiel_cascade_spec.rb`

**Interfaces:**
- Produces: `ContextualFilter#empty_label` → « Aucun choix disponible pour « <valeur> ». Modifiez « <pilote> » si nécessaire. » quand le pilote est renseigné ; inchangé quand il est vide.

- [ ] **Step 1 : Adapter les expectations (échec attendu)**

Dans `spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb`, l'exemple « annonce l'absence de résultat pour la valeur du pilote » attend désormais :

```ruby
expect(described_class.for(type_de_champ: rdp_tdc, dossier: dossier.reload).empty_label)
  .to eq('Aucun choix disponible pour « Plants ». Modifiez « Type de produit » si nécessaire.')
```

Même remplacement dans `spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb` (exemple « Aucun résultat pour ») et dans `spec/system/users/referentiel_cascade_spec.rb` si la chaîne « Aucun résultat pour » y apparaît (`grep -n "Aucun résultat" spec/`).

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb -e 'empty_label'` → FAIL.

- [ ] **Step 2 : Locales et service**

`config/locales/shared.fr.yml` :

```yaml
        filter_no_match: "Aucun choix disponible pour « %{value} ». Modifiez « %{pilot} » si nécessaire."
```

`config/locales/shared.en.yml` :

```yaml
        filter_no_match: "No option available for “%{value}”. Change “%{pilot}” if needed."
```

`app/lib/referentiel_de_polynesie/contextual_filter.rb`, méthode `empty_label`, branche pilote renseigné :

```ruby
      I18n.t('shared.champs.referentiel_de_polynesie.filter_no_match', value: pilot_value, pilot: pilot_libelle)
```

- [ ] **Step 3 : Vérifier**

Run: `bundle exec rspec spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb` → PASS.

- [ ] **Step 4 : Commit**

```bash
git add config/locales/shared.fr.yml config/locales/shared.en.yml app/lib/referentiel_de_polynesie/contextual_filter.rb spec/lib/referentiel_de_polynesie/contextual_filter_spec.rb spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb spec/system/users/referentiel_cascade_spec.rb
git commit -m "fix(referentiel): message d’état vide orienté usager pour la cascade"
```

---

### Task 13 : Déplacer la configuration du filtre vers le panneau 3 du wizard

**Files:**
- Create: `app/components/referentiels/referentiel_filter_component.rb`, `app/components/referentiels/referentiel_filter_component/referentiel_filter_component.html.haml`
- Modify: `app/components/referentiels/prefill_and_display_component.html.haml` (rendre le nouveau composant sous les deux tableaux)
- Modify: `app/controllers/administrateurs/referentiels_controller.rb:55-64` (`update_prefill_and_display_type_de_champ`) + nouveau `referentiel_filter_params`
- Modify: `app/components/types_de_champ_editor/champ_component/champ_component.html.haml` (supprimer le bloc `-# pf: cascade — restreindre…`)
- Modify: `app/components/types_de_champ_editor/champ_component.rb` (supprimer `referentiel_filter_enabled?`, `referentiel_filter_value`, `referentiel_filter_baserow_options`, `referentiel_filter_baserow_fields_unavailable?`, `referentiel_filter_pilot_options`, `fetch_referentiel_filter_baserow_fields`)
- Modify: `app/controllers/administrateurs/types_de_champ_controller.rb` (retirer `referentiel_filter_form: [...]` du permit ; garder le `.reject { _1 == :referentiel_filter }`)
- Modify: `app/components/types_de_champ_editor/info_referentiel_component.rb` + `.html.haml` (rappel en lecture seule)
- Test: Create `spec/components/referentiels/referentiel_filter_component_spec.rb` ; Modify `spec/controllers/administrateurs/referentiels_controller_spec.rb` (describe `#update_prefill_and_display_type_de_champ`), `spec/components/types_de_champ_editor/champ_component_spec.rb` (supprimer le describe « filtre contextuel », ajouter un exemple sur le rappel dans `InfoReferentielComponent` ou créer `spec/components/types_de_champ_editor/info_referentiel_component_spec.rb`), `spec/controllers/administrateurs/types_de_champ_controller_spec.rb` (supprimer le context « filtre contextuel »)

**Interfaces:**
- Produces: `Referentiels::ReferentielFilterComponent.new(procedure:, type_de_champ:, referentiel:)` — rendu seulement si `type_de_champ.referentiel_de_polynesie? && type_de_champ.table_id.present?` ; champs de formulaire `type_de_champ[referentiel_filter_form][enabled|baserow_field_id|pilot_column_id]` (mêmes noms qu'avant, consommés par `TypeDeChamp#referentiel_filter_form=`).
- Consumes: `ReferentielDePolynesie::API.table_fields(table_id)`, `ContextualFilter::FILTERABLE_BASEROW_TYPES`, `ProcedureRevisionTypeDeChamp#pilot_columns_for_referentiel_filter`, `Column#h_id[:column_id]`, `Column#label`.

- [ ] **Step 1 : Spec du nouveau composant (échec)**

Créer `spec/components/referentiels/referentiel_filter_component_spec.rb` :

```ruby
# frozen_string_literal: true

RSpec.describe Referentiels::ReferentielFilterComponent, type: :component do
  let(:referentiel) { create(:baserow_referentiel) } # baserow://24
  let(:procedure) do
    create(:procedure, types_de_champ_public: [
      { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'] },
      { type: :date, libelle: 'Date' },
      { type: :referentiel_de_polynesie, libelle: 'Produit', referentiel: },
    ])
  end
  let(:pilot_tdc) { procedure.draft_revision.types_de_champ_public.first }
  let(:type_de_champ) { procedure.draft_revision.types_de_champ_public.third }
  let(:fields) do
    {
      1 => { name: 'Nom', type: 'text', select_options: [] },
      12 => { name: 'Catégorie', type: 'single_select', select_options: [{ id: 100, value: 'Semences' }] },
      20 => { name: 'Fichier', type: 'file', select_options: [] },
    }
  end
  let(:component) { described_class.new(procedure:, type_de_champ:, referentiel:) }

  before { allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(fields) }

  subject { render_inline(component) }

  it 'affiche la case décochée et les deux listes masquées par défaut' do
    subject
    expect(page).to have_text('Indiquez si les lignes proposées doivent être restreintes selon un champ du formulaire')
    expect(page).to have_unchecked_field('Restreindre les lignes proposées')
    expect(page).to have_css('[data-hide-target-target="toHide"].fr-hidden')
    expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', with_options: ['Nom', 'Catégorie'])
    expect(page).not_to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', with_options: ['Fichier'])
    expect(page).to have_select('type_de_champ[referentiel_filter_form][pilot_column_id]', with_options: ['Type de produit'])
    expect(page).not_to have_select('type_de_champ[referentiel_filter_form][pilot_column_id]', with_options: ['Date'])
  end

  it 'affiche la case cochée et les listes visibles quand un filtre est configuré' do
    type_de_champ.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}" })
    subject
    expect(page).to have_checked_field('Restreindre les lignes proposées')
    expect(page).to have_css('[data-hide-target-target="toHide"]:not(.fr-hidden)')
    expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', selected: 'Catégorie')
    expect(page).to have_select('type_de_champ[referentiel_filter_form][pilot_column_id]', selected: 'Type de produit')
  end

  it 'garde la colonne en cache et prévient quand Baserow est injoignable' do
    allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(nil)
    type_de_champ.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => "type_de_champ/#{pilot_tdc.stable_id}" })
    subject
    expect(page).to have_select('type_de_champ[referentiel_filter_form][baserow_field_id]', selected: 'Catégorie')
    expect(page).to have_text('Colonnes indisponibles pour le moment')
  end

  context 'pour un référentiel upstream (API)' do
    let(:referentiel) { create(:api_referentiel, :exact_match) }
    let(:procedure) { create(:procedure, types_de_champ_public: [{ type: :referentiel, referentiel: }]) }
    let(:type_de_champ) { procedure.draft_revision.types_de_champ_public.first }

    it 'ne rend rien' do
      expect(subject.to_html).to be_empty
    end
  end
end
```

Run: `bundle exec rspec spec/components/referentiels/referentiel_filter_component_spec.rb` → FAIL (`NameError`).

- [ ] **Step 2 : Composant**

`app/components/referentiels/referentiel_filter_component.rb` :

```ruby
# frozen_string_literal: true

# pf: cascade — troisième section du panneau « préremplir et afficher » : restreindre les lignes
# proposées par le référentiel de Polynésie selon un champ du formulaire (colonne Baserow ↔ pilote).
# Vit ici, avec le préremplissage et l'affichage, parce qu'il relie les colonnes Baserow au
# formulaire ; la carte du champ ne garde qu'un rappel en lecture seule.
class Referentiels::ReferentielFilterComponent < Referentiels::MappingFormBase
  def render?
    type_de_champ.referentiel_de_polynesie? && type_de_champ.table_id.present?
  end

  def enabled?
    type_de_champ.referentiel_filter?
  end

  def current_value(key)
    Hash(type_de_champ.referentiel_filter)[key.to_s]
  end

  # pf: colonnes Baserow filtrables ; repli sur la colonne en cache si Baserow est injoignable
  def baserow_options
    return @baserow_options if defined?(@baserow_options)

    fields = fetch_fields
    @fields_unavailable = fields.nil?
    options = Hash(fields).filter_map do |id, field|
      [field[:name], id] if field[:type].in?(ReferentielDePolynesie::ContextualFilter::FILTERABLE_BASEROW_TYPES)
    end
    if options.empty? && current_value(:baserow_field_id).present?
      options = [[current_value(:baserow_field_name), current_value(:baserow_field_id).to_i]]
    end
    @baserow_options = options
  end

  def fields_unavailable?
    baserow_options
    @fields_unavailable
  end

  def pilot_options
    coordinate = procedure.draft_revision.coordinate_for(type_de_champ)
    return [] if coordinate.nil?

    coordinate.pilot_columns_for_referentiel_filter.map { [_1.label, _1.h_id[:column_id]] }
  end

  def field_id(suffix) = "referentiel-filter-#{type_de_champ.stable_id}-#{suffix}"

  private

  def fetch_fields
    ReferentielDePolynesie::API.table_fields(type_de_champ.table_id)
  rescue StandardError
    nil
  end
end
```

`app/components/referentiels/referentiel_filter_component/referentiel_filter_component.html.haml` :

```haml
-# pf: cascade — restreindre les lignes proposées selon un champ du formulaire
.fr-mt-4w{ data: { controller: 'hide-target' } }
  %p.fr-text--regular.fr-text--sm.fr-mb-2w Indiquez si les lignes proposées doivent être restreintes selon un champ du formulaire
  .fr-toggle
    = check_box_tag 'type_de_champ[referentiel_filter_form][enabled]', '1', enabled?,
      id: field_id(:enabled),
      class: 'fr-toggle__input',
      data: { 'hide-target-target': 'source' }
    = label_tag field_id(:enabled), 'Restreindre les lignes proposées', class: 'fr-toggle__label fr-label'
  .flex.flex-gap.fr-mt-2w{ class: class_names('fr-hidden': !enabled?), data: { 'hide-target-target': 'toHide' } }
    .flex-grow
      = label_tag field_id(:baserow_field_id), 'Colonne du référentiel à filtrer', class: 'fr-label'
      = select_tag 'type_de_champ[referentiel_filter_form][baserow_field_id]',
        options_for_select(baserow_options, current_value(:baserow_field_id)),
        include_blank: 'Choisir une colonne',
        id: field_id(:baserow_field_id),
        class: 'fr-select'
      - if fields_unavailable?
        %p.fr-hint-text.fr-mb-0 Colonnes indisponibles pour le moment
    .flex-grow
      = label_tag field_id(:pilot_column_id), 'Champ du formulaire qui pilote le filtre', class: 'fr-label'
      = select_tag 'type_de_champ[referentiel_filter_form][pilot_column_id]',
        options_for_select(pilot_options, current_value(:pilot_column_id)),
        include_blank: 'Choisir un champ',
        id: field_id(:pilot_column_id),
        class: 'fr-select'
      %p.fr-hint-text.fr-mb-0 Seuls les champs texte ou à choix unique placés avant ce champ sont proposés.
```

Dans `app/components/referentiels/prefill_and_display_component.html.haml`, après la ligne `= render Referentiels::ReferentielDisplayComponent.new(...)` (même indentation) :

```haml
    -# pf: cascade — filtre contextuel du référentiel de Polynésie (ne rend rien pour un référentiel API)
    = render Referentiels::ReferentielFilterComponent.new(procedure: procedure, type_de_champ: type_de_champ, referentiel: referentiel)
```

Run: `bundle exec rspec spec/components/referentiels/referentiel_filter_component_spec.rb` → PASS.

- [ ] **Step 3 : Contrôleur du wizard (échec puis succès)**

Dans `spec/controllers/administrateurs/referentiels_controller_spec.rb`, `describe '#update_prefill_and_display_type_de_champ'`, ajouter un contexte (aligner `procedure`, `admin`, `sign_in` et la forme de l'appel sur les exemples voisins) :

```ruby
    context 'avec un filtre contextuel (referentiel_de_polynesie)' do
      let(:referentiel) { create(:baserow_referentiel, types_de_champ: [type_de_champ]) }
      let(:types_de_champ_public) do
        [
          { type: :drop_down_list, libelle: 'Type de produit', options: ['Semences', 'Plants'], stable_id: 3 },
          { type: :referentiel_de_polynesie, stable_id:, referentiel_mapping: },
        ]
      end
      let(:type_de_champ) { procedure.draft_revision.types_de_champ.find(&:referentiel_de_polynesie?) }
      let(:fields) { { 12 => { name: 'Catégorie', type: 'single_select', select_options: [] } } }

      before { allow(ReferentielDePolynesie::API).to receive(:table_fields).with('24').and_return(fields) }

      it 'enregistre le filtre avec le mapping' do
        patch :update_prefill_and_display_type_de_champ, params: {
          procedure_id: procedure.id, stable_id: type_de_champ.stable_id, id: referentiel.id,
          type_de_champ: {
            referentiel_mapping: referentiel_mapping,
            referentiel_filter_form: { enabled: '1', baserow_field_id: '12', pilot_column_id: 'type_de_champ/3' },
          },
        }
        expect(type_de_champ.reload.referentiel_filter).to eq('baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/3')
      end

      it 'efface le filtre quand la case est décochée' do
        type_de_champ.update!(referentiel_filter: { 'baserow_field_id' => 12, 'baserow_field_name' => 'Catégorie', 'pilot_column_id' => 'type_de_champ/3' })
        patch :update_prefill_and_display_type_de_champ, params: {
          procedure_id: procedure.id, stable_id: type_de_champ.stable_id, id: referentiel.id,
          type_de_champ: { referentiel_mapping: referentiel_mapping, referentiel_filter_form: { baserow_field_id: '12', pilot_column_id: 'type_de_champ/3' } },
        }
        expect(type_de_champ.reload.referentiel_filter).to be_nil
      end
    end
```

(Si `referentiel_mapping_params` exige `referentiel_mapping` présent, passer un mapping minimal comme dans les exemples voisins ; si le `stable_id: 3` de la factory n'est pas respecté, utiliser `"type_de_champ/#{pilot.stable_id}"`.)

Run → FAIL (`referentiel_filter` reste nil).

Dans `app/controllers/administrateurs/referentiels_controller.rb`, remplacer la première ligne de `update_prefill_and_display_type_de_champ` :

```ruby
      # pf: cascade — le filtre contextuel est enregistré avec le mapping (même formulaire, panneau 3)
      attributes = { referentiel_mapping: @type_de_champ.safe_referentiel_mapping.deep_merge(referentiel_mapping_params) }
      attributes[:referentiel_filter_form] = referentiel_filter_params if referentiel_filter_params
      if @type_de_champ.update(attributes)
```

et ajouter en privé :

```ruby
    # pf: cascade — case + deux listes, consommées par TypeDeChamp#referentiel_filter_form=
    def referentiel_filter_params
      return nil unless params.dig(:type_de_champ, :referentiel_filter_form)

      params.require(:type_de_champ).require(:referentiel_filter_form).permit(:enabled, :baserow_field_id, :pilot_column_id).to_h
    end
```

Run: `bundle exec rspec spec/controllers/administrateurs/referentiels_controller_spec.rb` → PASS (anciens et nouveaux).

- [ ] **Step 4 : Retirer le bloc de la carte du champ, ajouter le rappel**

Dans `champ_component.html.haml`, supprimer entièrement le bloc commençant par `-# pf: cascade — restreindre les lignes proposées selon un autre champ du formulaire (lot A)` jusqu'à la fin de son `select_tag ... pilot_column_id` et son `%p.fr-hint-text`. Dans `champ_component.rb`, supprimer les six méthodes listées plus haut. Dans `types_de_champ_controller.rb`, retirer la ligne `referentiel_filter_form: [:enabled, :baserow_field_id, :pilot_column_id],`. Supprimer le describe « tdc referentiel_de_polynesie — filtre contextuel » de `champ_component_spec.rb` et le context « filtre contextuel d'un referentiel_de_polynesie » de `types_de_champ_controller_spec.rb`.

Rappel en lecture seule : dans `info_referentiel_component.rb`, ajouter :

```ruby
  # pf: cascade — rappel du filtre configuré, lu depuis les options (aucun appel Baserow)
  def referentiel_filter_summary
    return nil unless type_de_champ.referentiel_filter?

    config = Hash(type_de_champ.referentiel_filter)
    stable_id = config['pilot_column_id'].to_s[%r{\Atype_de_champ/(\d+)}, 1]
    pilot = stable_id && procedure.draft_revision.types_de_champ.find { _1.stable_id.to_s == stable_id }
    pilot_libelle = pilot&.libelle || 'champ supprimé'
    "Lignes restreintes selon « #{pilot_libelle} » (colonne « #{config['baserow_field_name']} »)"
  end
```

et dans `info_referentiel_component.html.haml`, avant le `%p.flex.column.align-end` final :

```haml
  - if referentiel_filter_summary
    %p.fr-text--sm.fr-mb-2w= referentiel_filter_summary
```

Test : dans `spec/components/types_de_champ_editor/champ_component_spec.rb` (ou une nouvelle `info_referentiel_component_spec.rb`), un exemple rend la carte d'un `referentiel_de_polynesie` avec `referentiel_filter` configuré et attend le texte « Lignes restreintes selon « Type de produit » (colonne « Catégorie ») », **sans** stub de `table_fields` (preuve qu'aucun appel Baserow n'est fait : `expect(ReferentielDePolynesie::API).not_to receive(:table_fields)`).

Run: `bundle exec rspec spec/components/types_de_champ_editor/ spec/controllers/administrateurs/types_de_champ_controller_spec.rb` → PASS.

- [ ] **Step 5 : Lint + commit**

```bash
bundle exec rubocop -a app/components/referentiels/referentiel_filter_component.rb app/controllers/administrateurs/referentiels_controller.rb app/components/types_de_champ_editor/champ_component.rb app/components/types_de_champ_editor/info_referentiel_component.rb app/controllers/administrateurs/types_de_champ_controller.rb spec/components/referentiels/referentiel_filter_component_spec.rb spec/controllers/administrateurs/referentiels_controller_spec.rb spec/components/types_de_champ_editor/ spec/controllers/administrateurs/types_de_champ_controller_spec.rb
bundle exec haml-lint app/components/referentiels/referentiel_filter_component/ app/components/referentiels/prefill_and_display_component.html.haml app/components/types_de_champ_editor/champ_component/champ_component.html.haml app/components/types_de_champ_editor/info_referentiel_component/
git add -A app/components/referentiels/ app/controllers/administrateurs/ app/components/types_de_champ_editor/ spec/components/ spec/controllers/administrateurs/
git commit -m "refactor(referentiel): déplace la configuration du filtre contextuel dans le wizard « Configurer le champ »"
```

---

### Task 14 : Case « option autre » au standard DSFR

**Files:**
- Modify: `app/components/types_de_champ_editor/champ_component/champ_component.html.haml` (bloc `-# pf: option « autre » avec texte libre pour le référentiel de Polynésie`)

- [ ] **Step 1 : Remplacer le bloc**

```haml
          -# pf: option « autre » avec texte libre pour le référentiel de Polynésie
          - if type_de_champ.referentiel_de_polynesie?
            .cell.fr-mt-2w
              .fr-toggle
                = form.check_box :drop_down_other, id: dom_id(type_de_champ, :drop_down_other), class: 'fr-toggle__input'
                = form.label :drop_down_other, 'Proposer une option « autre » avec un texte libre', for: dom_id(type_de_champ, :drop_down_other), class: 'fr-toggle__label fr-label'
```

(même patron que `collapsible_explanation_enabled` et `pj_auto_purge` dans ce fichier).

- [ ] **Step 2 : Vérifier et committer**

Run: `bundle exec haml-lint app/components/types_de_champ_editor/champ_component/champ_component.html.haml && bundle exec rspec spec/components/types_de_champ_editor/champ_component_spec.rb` → PASS.

```bash
git add app/components/types_de_champ_editor/champ_component/champ_component.html.haml
git commit -m "style(referentiel): case « option autre » au standard DSFR (toggle)"
```

---

### Task 15 : Libellés par défaut du mapping sans le préfixe `$.`

**Files:**
- Modify: `app/components/referentiels/mapping_form_base.rb:36-39` (décommenter `display_jsonpath`, tag `# pf:`)
- Modify: `app/components/referentiels/mapping_form_component.rb:38-44` (`enabled_libelle_tag`)
- Test: `spec/components/referentiels/mapping_form_component_spec.rb`

**Interfaces:**
- Produces: `Referentiels::MappingFormBase#display_jsonpath(jsonpath)` → `jsonpath.delete_prefix('$.')`. Les **clés** du mapping restent les jsonpaths complets (aucun changement de données) ; seule la valeur par défaut du champ « libellé » change.

- [ ] **Step 1 : Test (échec)**

Dans `spec/components/referentiels/mapping_form_component_spec.rb`, dans le contexte qui rend le formulaire avec une réponse (`last_response_body`) contenant une clé, ajouter :

```ruby
      it 'propose un libellé par défaut sans le préfixe jsonpath « $. »' do
        expect(page).to have_field("type_de_champ[referentiel_mapping][$.jsonpath][libelle]", with: 'jsonpath')
      end
```

(adapter le nom exact de la clé à celles du spec existant ; le champ est un `text_field_tag` dont le nom est `attribute_name(jsonpath, 'libelle')`).

Run → FAIL (valeur `$.jsonpath`).

- [ ] **Step 2 : Implémenter**

`mapping_form_base.rb`, remplacer le bloc commenté par :

```ruby
  # pf: libellé par défaut sans le préfixe jsonpath « $. » — l'admin le retirait à la main à
  # chaque colonne (retour de recette 2026-09-15). Les clés du mapping restent les jsonpaths
  # complets ; seule la valeur proposée dans le champ « libellé » change.
  def display_jsonpath(jsonpath)
    jsonpath.delete_prefix('$.')
  end
```

`mapping_form_component.rb`, `enabled_libelle_tag` :

```ruby
      lookup_existing_value(jsonpath, "libelle") || display_jsonpath(jsonpath),
```

- [ ] **Step 3 : Vérifier et committer**

Run: `bundle exec rspec spec/components/referentiels/ spec/controllers/administrateurs/referentiels_controller_spec.rb` → PASS.

```bash
git add app/components/referentiels/mapping_form_base.rb app/components/referentiels/mapping_form_component.rb spec/components/referentiels/mapping_form_component_spec.rb
git commit -m "feat(referentiel): libellé de mapping proposé sans le préfixe « $. »"
```

---

### Task 16 : Non-régression, documentation, spec

**Files:**
- Modify: `docs/superpowers/specs/2026-06-17-referentiel-polynesie-filtres-contextuels-design.md` §1 (éditeur : la configuration est dans le panneau 3 du wizard ; la carte du champ porte un rappel ; règle de placement)
- Modify: `french_polynesia.md` (section cascade : chemin de configuration)

- [ ] **Step 1 : Suites**

```bash
bundle exec rspec spec/components/referentiels/ spec/components/types_de_champ_editor/ spec/components/editable_champ/referentiel_de_polynesie_component_spec.rb spec/controllers/administrateurs/referentiels_controller_spec.rb spec/controllers/administrateurs/types_de_champ_controller_spec.rb spec/lib/referentiel_de_polynesie/ spec/models/champs/referentiel_de_polynesie_champ_spec.rb spec/validators/types_de_champ/ spec/controllers/data_sources/
NO_HEADLESS= bundle exec rspec spec/system/users/referentiel_cascade_spec.rb spec/system/users/referentiel_dlnuf_spec.rb spec/system/administrateurs/ -e referentiel
```

Expected: 0 failures (relancer une fois une spec système qui échouerait juste après un rebuild Vite).

- [ ] **Step 2 : Lint global du diff**

```bash
git diff --name-only 7533303bf8...HEAD -- '*.rb' | xargs bundle exec rubocop
git diff --name-only 7533303bf8...HEAD -- '*.haml' | xargs bundle exec haml-lint
bundle exec i18n-tasks missing --locales fr && bundle exec i18n-tasks unused --locale en
```

- [ ] **Step 3 : Documentation**

Spec §1 « Éditeur de formulaire » : remplacer le paragraphe sur la case et les deux listes dans la carte du champ par : la configuration vit dans le **panneau 3 du wizard « Configurer le champ »** (avec le préremplissage et l'affichage), sous forme d'une section « Indiquez si les lignes proposées doivent être restreintes selon un champ du formulaire » (toggle + deux listes) ; la carte du champ affiche un rappel en lecture seule « Lignes restreintes selon « … » (colonne « … ») » sans appel Baserow. Ajouter la règle de placement : « ce qui parle du formulaire reste dans le champ (obligatoire, description, option autre) ; ce qui relie les colonnes Baserow au formulaire va dans Configurer le champ (mode, indications, préremplissage, affichage, filtre) ». Message d'état vide (§4) : nouvelle formulation.

`french_polynesia.md`, section cascade : « Configuration dans le wizard « Configurer le champ », panneau « préremplir et afficher », section « Restreindre les lignes proposées » … ».

- [ ] **Step 4 : Commit**

```bash
git add docs/superpowers/specs/2026-06-17-referentiel-polynesie-filtres-contextuels-design.md french_polynesia.md
git commit -m "docs(referentiel): configuration du filtre dans le wizard et règle de placement des options"
```

---

## Self-review

- Couverture des retours : message usager → T12 ; déplacement + rappel + zéro appel Baserow dans l'éditeur → T13 ; DSFR « option autre » → T14 ; préfixe `$.` → T15 ; documentation → T16.
- Cohérence des noms : `referentiel_filter_form` (setter T1 inchangé) réutilisé par le nouveau composant et le contrôleur du wizard ; `pilot_columns_for_referentiel_filter` et `h_id[:column_id]` (T8) réutilisés ; `FILTERABLE_BASEROW_TYPES` (T3).
- Hors périmètre volontaire : `$.order` proposé au mapping (champ technique Baserow), débordement horizontal du tableau d'affichage (chantier grille différé), diagnostic admin des valeurs sans ligne (backlog).
