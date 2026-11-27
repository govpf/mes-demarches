# Backport de la vue instructeur « Afficher la version d'origine » — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettre à un instructeur de consulter un dossier tel qu'il a été déposé — y compris les champs retirés du formulaire par une publication ultérieure, pièces jointes téléchargeables — sans attendre l'intégration des 87 releases upstream de retard.

**Architecture :** On backporte la fonctionnalité introduite upstream dans la release `2026-01-20-01`. Le mécanisme repose sur un pseudo-stream de lecture `user:history` : au lieu de lire les champs du stream `main` filtrés par la révision courante, on lit **tous** les champs du dossier antérieurs au dépôt et on garde la dernière version de chacun. Combiné au fait de reprojeter le dossier sur `submitted_revision`, cela fait réapparaître les champs supprimés avec leurs pièces jointes. Aucune donnée n'est déplacée ni dupliquée : c'est une lecture différente de lignes déjà en base.

**Tech Stack :** Ruby 3.3.2, Rails 7.0.8.4, RSpec, Capybara/Playwright pour les specs système, HAML (upstream a migré vers ERB, nous restons en HAML).

## Global Constraints

- Tout texte d'interface en français utilise l'apostrophe française `'` et les guillemets `« »`, jamais `'`. Les assertions de tests système doivent utiliser les mêmes caractères.
- Toute divergence ou ajout spécifique PF est marqué par un commentaire `# pf:` expliquant le pourquoi.
- Le code doit rester **au plus près de la forme upstream** (mêmes noms de constantes, méthodes et routes) : upstream a renommé `champs` → `champ_data`, et plus notre version ressemble à la leur, plus le merge des 87 releases se résoudra proprement.
- Référence upstream : tag `2026-07-29-02`, fichiers `app/models/concerns/dossier_stream_concern.rb`, `app/models/concerns/dossier_champs_concern.rb:342-350`, `app/controllers/instructeurs/dossiers_controller.rb:75`, `config/routes/instructeur.rb:51`.
- Aucune migration de base de données. Aucune modification du stream stocké en base.
- `bundle exec rails lint` doit passer avant chaque commit.

---

## File Structure

| Fichier | Responsabilité |
|---|---|
| `app/models/champ.rb` | Ajout de la constante `USER_HISTORY_STREAM` à côté des autres constantes de stream |
| `app/models/concerns/dossier_champs_concern.rb` | Branche de lecture `user:history` dans `champs_on_stream` + helper `with_user_history_stream` |
| `config/routes.rb` | Route `original` sur le membre dossier instructeur |
| `app/controllers/instructeurs/dossiers_controller.rb` | Action `show_submitted_revision` + `before_action :dossier_with_submitted_revision` |
| `app/views/instructeurs/dossiers/show_submitted_revision.html.haml` | Vue minimale rendant la demande, sans navigation |
| `app/views/shared/dossiers/_demande.html.haml` | Bannière « ce n'est pas la version d'origine » côté instructeur |
| `config/locales/fr.yml` | Libellés de la bannière et du titre de la vue |
| `spec/models/concerns/dossier_champs_concern_spec.rb` | Specs unitaires de la branche de stream |
| `spec/controllers/instructeurs/dossiers_controller_spec.rb` | Spec de l'action et de la redirection |
| `spec/system/instructeurs/instructeur_version_origine_spec.rb` | Spec système bout-en-bout |

---

### Task 1 : la branche de lecture `user:history`

C'est le cœur du backport. Le reste n'est que du câblage.

**Files:**
- Modify: `app/models/champ.rb:285-287` (constantes de stream)
- Modify: `app/models/concerns/dossier_champs_concern.rb:328-330` (helpers `with_*_stream`) et `:376-383` (`champs_on_stream`)
- Test: `spec/models/concerns/dossier_champs_concern_spec.rb`

**Interfaces:**
- Consomme : rien (première tâche).
- Produit :
  - `Champ::USER_HISTORY_STREAM` → `'user:history'`
  - `Dossier#with_user_history_stream(&block)` → avec bloc, exécute le bloc sur ce stream puis restaure ; sans bloc, positionne `@stream` et retourne `self` (comportement de `with_stream` existant, `dossier_champs_concern.rb:352`)
  - `Dossier#champs_on_stream` gagne une branche : quand `stream == Champ::USER_HISTORY_STREAM`, retourne les champs tels qu'au dépôt, **champs hors révision compris**

- [ ] **Step 1 : Écrire le test qui échoue**

Ajouter dans `spec/models/concerns/dossier_champs_concern_spec.rb` :

```ruby
describe 'user history stream' do
  # Un champ text rempli, puis supprimé du formulaire par une nouvelle révision.
  let(:procedure) do
    create(:procedure, :published, types_de_champ_public: [
      { type: :text, libelle: 'Champ conservé' },
      { type: :text, libelle: 'Champ supprimé' }
    ])
  end
  # :with_populated_champs est indispensable — sans lui la factory ne crée
  # aucune ligne `champs` et `find_by(stable_id:)` renverrait nil.
  let(:dossier) { create(:dossier, :en_construction, :with_populated_champs, procedure:) }
  let(:tdc_conserve) { procedure.active_revision.types_de_champ_public.find { _1.libelle == 'Champ conservé' } }
  let(:tdc_supprime) { procedure.active_revision.types_de_champ_public.find { _1.libelle == 'Champ supprimé' } }

  before do
    # 1. l'usager remplit les deux champs
    dossier.champs.find_by(stable_id: tdc_conserve.stable_id).update(value: 'valeur 0')
    dossier.champs.find_by(stable_id: tdc_supprime.stable_id).update(value: 'valeur 1')
    # 2. on simule le dépôt APRÈS la saisie : en_construction_at doit être
    #    postérieur à updated_at des champs, sinon le filtre les exclut.
    dossier.update_columns(en_construction_at: Time.current, submitted_revision_id: dossier.revision_id)
    # 3. l'admin supprime le second champ et republie
    procedure.draft_revision.remove_type_de_champ(tdc_supprime.stable_id)
    procedure.publish_revision!(procedure.administrateurs.first)
    dossier.reload.rebase!
    dossier.reload
  end

  it 'masque le champ supprimé sur le stream main' do
    expect(dossier.project_champs_public.map(&:libelle)).to eq(['Champ conservé'])
  end

  it 'expose le champ supprimé sur le stream user:history' do
    dossier.revision = dossier.submitted_revision
    dossier.with_user_history_stream

    libelles = dossier.project_champs_public.map(&:libelle)
    expect(libelles).to include('Champ supprimé')

    champ = dossier.project_champs_public.find { _1.libelle == 'Champ supprimé' }
    expect(champ.value).to eq('valeur 1')
  end

  it 'ignore les modifications postérieures au dépôt' do
    dossier.update_columns(en_construction_at: 1.hour.ago)
    dossier.revision = dossier.submitted_revision
    dossier.with_user_history_stream

    expect(dossier.project_champs_public.find { _1.libelle == 'Champ supprimé' }.value).to be_nil
  end

  it 'retombe sur le stream main quand le dossier n’a jamais été déposé' do
    brouillon = create(:dossier, :with_populated_champs, procedure:)
    expect(brouillon.en_construction_at).to be_nil
    brouillon.with_user_history_stream
    expect { brouillon.project_champs_public }.not_to raise_error
  end
end
```

- [ ] **Step 2 : Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/models/concerns/dossier_champs_concern_spec.rb -e "user history stream"`
Expected: FAIL avec `NoMethodError: undefined method 'with_user_history_stream'`

- [ ] **Step 3 : Ajouter la constante de stream**

Dans `app/models/champ.rb`, à côté des constantes existantes (ligne ~285) :

```ruby
  MAIN_STREAM = 'main'
  USER_BUFFER_STREAM = 'user:buffer'
  HISTORY_STREAM = 'history:'
  # pf: backport upstream 2026-01-20-01 — pseudo-stream de LECTURE seule pour la
  # vue instructeur « version d'origine ». Aucune ligne n'est jamais stockée
  # avec cette valeur : elle ne sert qu'à sélectionner un mode de lecture dans
  # Dossier#champs_on_stream. Ne pas confondre avec HISTORY_STREAM, qui est un
  # préfixe réellement persisté (history:<horodatage>).
  USER_HISTORY_STREAM = 'user:history'
```

- [ ] **Step 4 : Ajouter le helper de stream**

Dans `app/models/concerns/dossier_champs_concern.rb`, juste après `with_main_stream` (ligne ~330) :

```ruby
  def with_user_history_stream(&block)
    with_stream(Champ::USER_HISTORY_STREAM, &block)
  end
```

- [ ] **Step 5 : Ajouter la branche de lecture**

Remplacer `champs_on_stream` (`dossier_champs_concern.rb:376-383`) par :

```ruby
  def champs_on_stream
    @champs_on_stream ||= case stream
    when Champ::USER_BUFFER_STREAM
      (champs_on_user_buffer_stream + champs_on_main_stream).uniq(&:public_id)
    when Champ::USER_HISTORY_STREAM
      # pf: backport upstream 2026-01-20-01 (dossier_champs_concern.rb:342-350).
      # On part de `champs` et NON de `champs_in_revision` : tout l'intérêt de
      # cette vue est d'exposer les champs retirés du formulaire par une
      # révision postérieure au dépôt, qui sont par définition hors révision.
      # Sans en_construction_at il n'y a pas de dépôt de référence : on
      # retombe sur main plutôt que de renvoyer une liste vide.
      if en_construction_at.nil?
        champs_on_main_stream
      else
        champs
          .reject(&:user_buffer_stream?)
          .filter { _1.updated_at <= en_construction_at }
          .sort_by(&:updated_at)
          .reverse
          .uniq(&:public_id)
      end
    else
      champs_on_main_stream
    end
  end
```

- [ ] **Step 6 : Lancer les tests pour vérifier qu'ils passent**

Run: `bundle exec rspec spec/models/concerns/dossier_champs_concern_spec.rb`
Expected: PASS, y compris les tests préexistants du fichier.

- [ ] **Step 7 : Vérifier la non-régression sur les streams existants**

Run: `bundle exec rspec spec/models/concerns/dossier_rebase_concern_spec.rb spec/models/dossier_spec.rb`
Expected: PASS. Cette branche ne doit rien changer aux streams `main` et `user:buffer`.

- [ ] **Step 8 : Commit**

```bash
git add app/models/champ.rb app/models/concerns/dossier_champs_concern.rb spec/models/concerns/dossier_champs_concern_spec.rb
git commit -m "feat(instruction): lecture des champs tels qu'au dépôt via le stream user:history"
```

---

### Task 2 : route, action et vue

**Files:**
- Modify: `config/routes.rb` (bloc `member do` des dossiers instructeur, vers la ligne 528)
- Modify: `app/controllers/instructeurs/dossiers_controller.rb:14-19` (before_actions) et après `show` (ligne ~70)
- Create: `app/views/instructeurs/dossiers/show_submitted_revision.html.haml`
- Test: `spec/controllers/instructeurs/dossiers_controller_spec.rb`

**Interfaces:**
- Consomme : `Dossier#with_user_history_stream` (Task 1), `Dossier#revision_changed_since_submitted?` (existe déjà, `dossier.rb:1151`), `Dossier#submitted_revision` (association existante, `dossier.rb:132`).
- Produit :
  - route nommée `original` sur le membre dossier — le helper exact est à relever avec `bin/rails routes` (Step 2), il sera de la forme `original_instructeur_procedure_dossier_path`
  - `Instructeurs::DossiersController#show_submitted_revision`
  - `Instructeurs::DossiersController#dossier_with_submitted_revision` (privée) : reprojette le dossier sur sa révision de dépôt, ou redirige vers le dossier si la révision n'a pas changé

- [ ] **Step 1 : Ajouter la route**

Dans `config/routes.rb`, dans le bloc `member do` des dossiers instructeur (à côté de `get 'messagerie'`, vers la ligne 537) :

```ruby
              get 'original' => 'dossiers#show_submitted_revision', as: :original
```

- [ ] **Step 2 : Relever le nom exact du helper de route**

Run: `bin/rails routes | grep original`
Noter le nom du helper affiché en première colonne. Il sera utilisé tel quel à la Task 3. Ne pas deviner ce nom.

- [ ] **Step 3 : Écrire le test qui échoue**

Ajouter dans `spec/controllers/instructeurs/dossiers_controller_spec.rb`, dans le `describe` existant du controller :

```ruby
describe '#show_submitted_revision' do
  let(:procedure) { create(:procedure, :published, types_de_champ_public: [{ type: :text, libelle: 'Champ supprimé' }]) }
  let(:dossier) { create(:dossier, :en_construction, procedure:) }
  let(:instructeur) { create(:instructeur, procedures: [procedure]) }

  before { sign_in(instructeur.user) }

  subject do
    get :show_submitted_revision, params: { procedure_id: procedure.id, dossier_id: dossier.id }
  end

  context 'quand la révision n’a pas changé depuis le dépôt' do
    before { dossier.update_columns(submitted_revision_id: dossier.revision_id) }

    it 'redirige vers le dossier' do
      expect(subject).to redirect_to(instructeur_dossier_path(procedure, dossier))
    end
  end

  context 'quand la révision a changé depuis le dépôt' do
    let(:tdc) { procedure.active_revision.types_de_champ_public.first }

    before do
      dossier.update_columns(en_construction_at: Time.current, submitted_revision_id: dossier.revision_id)
      procedure.draft_revision.remove_type_de_champ(tdc.stable_id)
      procedure.publish_revision!(procedure.administrateurs.first)
      dossier.reload.rebase!
    end

    it 'affiche la version déposée' do
      expect(subject).to have_http_status(:ok)
      expect(assigns(:dossier).revision_id).to eq(assigns(:dossier).submitted_revision_id)
    end
  end
end
```

- [ ] **Step 4 : Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/controllers/instructeurs/dossiers_controller_spec.rb -e "show_submitted_revision"`
Expected: FAIL avec `AbstractController::ActionNotFound` ou `The action 'show_submitted_revision' could not be found`

- [ ] **Step 5 : Déclarer les before_actions**

Dans `app/controllers/instructeurs/dossiers_controller.rb`, ajouter `:show_submitted_revision` aux trois `before_action` suivants (lignes 14, 16, 17) et ajouter le nouveau :

```ruby
    before_action :redirect_on_dossier_not_found, only: [:show, :show_submitted_revision]
    before_action :dossier_with_champs, only: [:show, :show_submitted_revision]
    before_action :dossier_with_submitted_revision, only: [:show_submitted_revision]
    before_action :set_gallery_attachments, only: [:show, :show_submitted_revision, :pieces_jointes, :annotations_privees, :avis, :messagerie, :personnes_impliquees, :reaffectation, :rendez_vous, :rdv_connection]
```

Attention : `dossier_with_submitted_revision` doit être déclaré **après** `dossier_with_champs`, qui charge `@dossier`.

- [ ] **Step 6 : Écrire l'action publique**

Dans le même fichier, juste après la méthode `show` (ligne ~70) :

```ruby
    # pf: backport upstream 2026-01-20-01. Affiche le dossier tel qu'il a été
    # déposé, y compris les champs retirés du formulaire depuis. Layout épuré :
    # cette vue est une consultation ponctuelle, pas un onglet d'instruction.
    def show_submitted_revision
      @demande_seen_at = current_instructeur.follows.find_by(dossier: dossier_with_champs)&.demande_seen_at
      render layout: 'empty_layout'
    end
```

- [ ] **Step 7 : Écrire le before_action privé**

Dans la section `private` du même controller, à côté de `dossier_with_champs` :

```ruby
    def dossier_with_submitted_revision
      if @dossier.revision_changed_since_submitted?
        @dossier.revision = @dossier.submitted_revision
        @dossier.with_user_history_stream
      else
        redirect_to instructeur_dossier_path(@dossier.procedure, @dossier)
      end
    end
```

- [ ] **Step 8 : Créer la vue**

Créer `app/views/instructeurs/dossiers/show_submitted_revision.html.haml` :

```haml
- content_for(:title, dossier_tab_title(@dossier, t('instructeurs.dossiers.show_submitted_revision.title')))

.fr-container.fr-mt-4w
  = render Dsfr::AlertComponent.new(state: :info, size: :sm, extra_class_names: 'fr-mb-4w') do |c|
    - c.with_body do
      %p= t('instructeurs.dossiers.show_submitted_revision.notice')

  = render partial: "shared/dossiers/demande", locals: { dossier: @dossier, demande_seen_at: @demande_seen_at, profile: 'instructeur' }
```

- [ ] **Step 9 : Ajouter les libellés**

Dans `config/locales/fr.yml`, sous `fr: instructeurs: dossiers:` (créer les clés si la hiérarchie n'existe pas encore) :

```yaml
        show_submitted_revision:
          title: "Version d'origine"
          notice: "Vous consultez le dossier tel qu'il a été déposé par l'usager. Le formulaire a évolué depuis : certains champs affichés ici ne font plus partie de la démarche."
```

- [ ] **Step 10 : Lancer les tests pour vérifier qu'ils passent**

Run: `bundle exec rspec spec/controllers/instructeurs/dossiers_controller_spec.rb`
Expected: PASS. Si un `NameError` sur une variable d'instance survient au rendu, c'est qu'un `before_action` manque dans la liste du Step 5 — l'ajouter et relancer.

- [ ] **Step 11 : Commit**

```bash
git add config/routes.rb app/controllers/instructeurs/dossiers_controller.rb app/views/instructeurs/dossiers/show_submitted_revision.html.haml config/locales/fr.yml spec/controllers/instructeurs/dossiers_controller_spec.rb
git commit -m "feat(instruction): route et vue « version d'origine » d'un dossier déposé"
```

---

### Task 3 : la bannière d'accès depuis l'onglet Demande

Sans elle, la vue existe mais personne ne la trouve.

**Files:**
- Modify: `app/views/shared/dossiers/_demande.html.haml:65-66`
- Modify: `config/locales/fr.yml`
- Test: couvert par la spec système de la Task 4

**Interfaces:**
- Consomme : le helper de route relevé au Step 2 de la Task 2, `Dossier#revision_changed_since_submitted?`.
- Produit : un lien visible pour `profile == 'instructeur'` uniquement.

- [ ] **Step 1 : Insérer la bannière**

Dans `app/views/shared/dossiers/_demande.html.haml`, juste après le `%h2` du titre « Demande » (ligne 65-66) et **avant** la ligne `- types_de_champ = dossier.revision.types_de_champ_public` :

```haml
  -# pf: backport upstream 2026-01-20-01. Signale à l'instructeur qu'il ne
  -# regarde pas la version déposée, et lui donne l'accès. Réservé à
  -# l'instructeur : côté usager, le dossier doit s'aligner sur la version
  -# officielle, pas exposer un historique.
  - if profile == 'instructeur' && dossier.revision_changed_since_submitted?
    = render Dsfr::AlertComponent.new(state: :info, size: :sm, extra_class_names: 'fr-icon-history-line fr-my-4v') do |c|
      - c.with_body do
        %p
          = t('views.shared.dossiers.demande.not_submitted_revision')
          = link_to t('views.shared.dossiers.demande.show_submitted_revision'), original_instructeur_dossier_path(dossier.procedure, dossier, statut: params[:statut]), class: 'fr-link'
```

Ce nom et cette signature suivent le motif déjà en place pour les autres routes membre du dossier instructeur — cf. `app/views/instructeurs/dossiers/_header_bottom.html.haml:10`, `pieces_jointes_instructeur_dossier_path(dossier.procedure, dossier, statut: params[:statut])`. Confronter au relevé du Step 2 de la Task 2 et corriger si le nom diffère.

- [ ] **Step 2 : Ajouter les libellés**

Dans `config/locales/fr.yml`, sous `fr: views: shared: dossiers: demande:` (la clé `form` y existe déjà) :

```yaml
            not_submitted_revision: "Il ne s'agit pas de la version d'origine déposée par l'usager :"
            show_submitted_revision: "Afficher la version d'origine"
```

- [ ] **Step 3 : Vérifier le rendu manuellement**

Run: `bin/rails s`
Ouvrir un dossier instructeur d'une démarche dont la révision a changé depuis le dépôt, vérifier que la bannière apparaît sous le titre « Demande » et que le lien fonctionne. Vérifier qu'elle **n'apparaît pas** côté usager sur le même dossier.

- [ ] **Step 4 : Vérifier le lint**

Run: `bundle exec rails lint`
Expected: aucune erreur.

- [ ] **Step 5 : Commit**

```bash
git add app/views/shared/dossiers/_demande.html.haml config/locales/fr.yml
git commit -m "feat(instruction): lien vers la version d'origine depuis l'onglet Demande"
```

---

### Task 4 : spec système bout-en-bout

C'est le test qui manquait en décembre 2024 et qui aurait attrapé la régression. Il doit couvrir le scénario réel de nos deux incidents : une pièce jointe sur un champ supprimé.

**Files:**
- Create: `spec/system/instructeurs/instructeur_version_origine_spec.rb`

**Interfaces:**
- Consomme : tout ce qui précède.
- Produit : rien (test terminal).

- [ ] **Step 1 : Écrire le test**

Créer `spec/system/instructeurs/instructeur_version_origine_spec.rb` :

```ruby
# frozen_string_literal: true

describe 'Instructeur — version d’origine d’un dossier déposé', js: true do
  let(:procedure) do
    create(:procedure, :published, types_de_champ_public: [
      { type: :text, libelle: 'Raison sociale' },
      { type: :piece_justificative, libelle: 'Liste des produits' }
    ])
  end
  let(:instructeur) { create(:instructeur, procedures: [procedure]) }
  let(:dossier) { create(:dossier, :en_construction, :with_populated_champs, procedure:) }
  let(:tdc_pj) { procedure.active_revision.types_de_champ_public.find(&:piece_justificative?) }

  before do
    # L'usager remplit le formulaire, pièce jointe incluse.
    # :with_populated_champs a créé les lignes `champs` : on attache le fichier
    # sur celle du champ pièce jointe.
    champ_pj = dossier.champs.find_by(stable_id: tdc_pj.stable_id)
    champ_pj.piece_justificative_file.attach(
      io: StringIO.new('contenu du tableur'),
      filename: 'liste-produits.xlsx',
      # on ne veut pas déclencher l'antivirus dans les tests
      metadata: { virus_scan_result: ActiveStorage::VirusScanner::SAFE }
    )

    # Le dépôt est postérieur à la saisie
    dossier.update_columns(en_construction_at: Time.current, submitted_revision_id: dossier.revision_id)

    # L'admin supprime le champ pièce jointe et republie
    procedure.draft_revision.remove_type_de_champ(tdc_pj.stable_id)
    procedure.publish_revision!(procedure.administrateurs.first)
    dossier.reload.rebase!

    login_as instructeur.user, scope: :user
  end

  scenario 'l’instructeur retrouve la pièce jointe du champ supprimé' do
    visit instructeur_dossier_path(procedure, dossier)

    # le champ supprimé n'est plus dans le formulaire courant
    expect(page).not_to have_content('Liste des produits')

    # la bannière propose la version d'origine
    expect(page).to have_content("Il ne s'agit pas de la version d'origine déposée par l'usager")
    click_on "Afficher la version d'origine"

    # le champ supprimé et son fichier réapparaissent
    expect(page).to have_content('Liste des produits')
    expect(page).to have_link('liste-produits.xlsx')
  end

  scenario 'aucune bannière quand la révision n’a pas changé depuis le dépôt' do
    autre_dossier = create(:dossier, :en_construction, :with_populated_champs, procedure:)
    autre_dossier.update_columns(submitted_revision_id: autre_dossier.revision_id)

    visit instructeur_dossier_path(procedure, autre_dossier)

    expect(page).not_to have_content("Afficher la version d'origine")
  end
end
```

- [ ] **Step 2 : Lancer le test**

Run: `bundle exec rspec spec/system/instructeurs/instructeur_version_origine_spec.rb`
Expected: PASS.

Si `have_link('liste-produits.xlsx')` échoue alors que le libellé du champ s'affiche, vérifier que `set_gallery_attachments` est bien dans le `only:` du `before_action` (Task 2, Step 5) : c'est lui qui alimente le rendu des pièces jointes.

- [ ] **Step 3 : Vérifier l'absence de régression sur l'instruction**

Run: `bundle exec rspec spec/system/instructeurs/ spec/controllers/instructeurs/`
Expected: PASS.

- [ ] **Step 4 : Commit**

```bash
git add spec/system/instructeurs/instructeur_version_origine_spec.rb
git commit -m "test(instruction): spec système de la version d'origine avec pièce jointe supprimée"
```

---

## Vérification finale

- [ ] `bundle exec rspec spec/models/concerns/dossier_champs_concern_spec.rb spec/models/concerns/dossier_rebase_concern_spec.rb spec/controllers/instructeurs/dossiers_controller_spec.rb spec/system/instructeurs/` → PASS
- [ ] `bundle exec rails lint` → PASS
- [ ] Contrôle manuel sur la démarche 2456 en recette : ouvrir un des 12 dossiers restaurés, vérifier que la bannière apparaît et que l'Excel est téléchargeable depuis la version d'origine
- [ ] Vérifier qu'aucun libellé n'utilise l'apostrophe droite `'`

## Ce que ce backport ne fait pas

À dire explicitement dans la description de la PR, pour éviter une fausse impression de sécurité :

- **C'est une fenêtre, pas une archive.** La vue lit des lignes en base. Dès que l'usager réédite et redépose son dossier, `remove_not_in_revision_champs!` détruit le champ hors révision et purge son fichier ; la vue devient alors vide pour ce champ, sans laisser de trace — pas même le nom du fichier.
- **Rien côté usager.** La bannière est réservée à l'instructeur. Un usager qui perd sa pièce jointe en rééditant n'a aucun moyen de voir ce qu'il y avait.
- **Rien côté admin.** L'administrateur qui publie une suppression de champ n'est toujours pas averti du nombre de dossiers et de fichiers impactés (traductions `delete_champ_html` et `breaking_change` mortes depuis `5e7585daea`, 2024-12-09). Chantier suivant.
