# Badge provider d'identité sur la page profil — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Afficher, à côté de chaque identité externe listée sur la page `/profil`, un badge indiquant le fournisseur d'identité (FranceConnect, Tātou, Microsoft, Google).

**Architecture:** Le fournisseur n'est aujourd'hui persisté nulle part sur `FranceConnectInformation` (FCI). On stocke le provider **par-FCI** dans la colonne `data` (jsonb, déjà présente et inutilisée) via un `store_accessor`, sans migration. On renseigne le provider à la création de la FCI (OmniAuth + FranceConnect) et on backfill les FCI existantes à la reconnexion. La vue profil affiche un badge DSFR quand le provider est connu.

**Tech Stack:** Ruby 3.3.2, Rails 7.0.8.4, RSpec, HAML, DSFR.

## Global Constraints

- Textes d'interface en français avec quote française « ' » (U+2019), pas la quote droite.
- Marquer toute spécificité PF d'un commentaire `# pf:`.
- Le provider stocké est **purement décoratif** : aucune décision de confiance/fusion ne doit s'appuyer sur `data.provider` (celles-ci restent sur `trusted_email_assertion` / `OmniAuthService::STRONG_IDENTITY_PROVIDERS`).
- Valeurs de provider utilisées : `particulier`, `google`, `microsoft`, `tatou` (libellés i18n `omniauth.provider.*` déjà présents dans `config/locales/fr.yml` et `en.yml`).
- Pas de migration de schéma (réutilisation de la colonne `data`).

---

## File Structure

- `app/models/france_connect_information.rb` — ajout `store_accessor :data, :provider`
- `app/services/omni_auth_service.rb` — pose du provider à la création + backfill à la reconnexion
- `app/services/france_connect_service.rb` — pose du provider `'particulier'` + backfill
- `app/views/users/profil/show.html.haml` — badge DSFR dans la liste des identités
- Tests : `spec/models/france_connect_information_spec.rb`, `spec/services/omni_auth_service_spec.rb`, `spec/services/france_connect_service_spec.rb`, `spec/controllers/users/profil_controller_spec.rb`

---

### Task 1: Accès `provider` sur FranceConnectInformation (store_accessor)

**Files:**
- Modify: `app/models/france_connect_information.rb:12`
- Test: `spec/models/france_connect_information_spec.rb`

**Interfaces:**
- Produces: `FranceConnectInformation#provider` (lecture), `#provider=` (écriture) ; la valeur est stockée dans la colonne jsonb `data` sous la clé `"provider"`.

- [ ] **Step 1: Write the failing test**

Ajouter dans `spec/models/france_connect_information_spec.rb` :

```ruby
describe '#provider (stocké dans data jsonb)' do
  it 'écrit et relit le provider via la colonne data' do
    fci = FranceConnectInformation.new(france_connect_particulier_id: '42', provider: 'tatou')
    expect(fci.provider).to eq('tatou')
    expect(fci.data).to eq('provider' => 'tatou')
  end

  it 'renvoie nil quand aucun provider n’a été renseigné' do
    fci = FranceConnectInformation.new(france_connect_particulier_id: '42')
    expect(fci.provider).to be_nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/models/france_connect_information_spec.rb -e "provider"`
Expected: FAIL — `unknown attribute 'provider'` (le writer n'existe pas encore).

- [ ] **Step 3: Write minimal implementation**

Dans `app/models/france_connect_information.rb`, juste après la ligne `attr_accessor :trusted_email_assertion` (ligne 12) :

```ruby
  # pf: le fournisseur d'identité (particulier=FranceConnect, google, microsoft, tatou)
  # est stocké par-FCI dans la colonne data (jsonb), sans migration. Purement décoratif :
  # aucune décision de confiance ne s'appuie dessus (voir OmniAuthService).
  store_accessor :data, :provider
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/models/france_connect_information_spec.rb -e "provider"`
Expected: PASS (2 examples).

- [ ] **Step 5: Commit**

```bash
git add app/models/france_connect_information.rb spec/models/france_connect_information_spec.rb
git commit -m "feat(pf): provider d'identité stocké par-FCI dans data (store_accessor)"
```

---

### Task 2: OmniAuthService — pose du provider à la création et backfill à la reconnexion

**Files:**
- Modify: `app/services/omni_auth_service.rb` (`find_or_retrieve_user_informations`, `retrieve_user_informations`)
- Test: `spec/services/omni_auth_service_spec.rb`

**Interfaces:**
- Consumes: `FranceConnectInformation#provider=` (Task 1).
- Produces: à l'issue de `OmniAuthService.find_or_retrieve_user_informations(provider, code)`, la FCI retournée a `provider == provider`, et une FCI persistée sans provider est mise à jour en base.

- [ ] **Step 1: Write the failing test**

Ajouter dans `spec/services/omni_auth_service_spec.rb` (au niveau `describe OmniAuthService do`) :

```ruby
describe '.find_or_retrieve_user_informations (provider persisté)' do
  let(:provider) { 'tatou' }
  let(:sub) { 'sub-123' }

  before do
    fetched = FranceConnectInformation.new(france_connect_particulier_id: sub)
    fetched.trusted_email_assertion = true
    allow(described_class).to receive(:retrieve_user_informations).with(provider, 'code').and_return(fetched)
  end

  context 'nouvelle identité (non persistée)' do
    it 'positionne le provider sur la FCI' do
      fci = described_class.find_or_retrieve_user_informations(provider, 'code')
      expect(fci.provider).to eq('tatou')
    end
  end

  context 'identité existante sans provider (backfill)' do
    let!(:existing) do
      create(:france_connect_information, france_connect_particulier_id: sub, user: create(:user))
    end

    it 'renseigne et persiste le provider manquant' do
      fci = described_class.find_or_retrieve_user_informations(provider, 'code')
      expect(fci.id).to eq(existing.id)
      expect(fci.provider).to eq('tatou')
      expect(existing.reload.provider).to eq('tatou')
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/omni_auth_service_spec.rb -e "provider persisté"`
Expected: FAIL — `provider` est `nil` (rien ne le pose encore).

- [ ] **Step 3: Write minimal implementation**

Dans `app/services/omni_auth_service.rb`, méthode `retrieve_user_informations` : ajouter `provider:` au `FranceConnectInformation.new(...)`.

Remplacer :

```ruby
    fci = FranceConnectInformation.new(
      gender: user_info[:gender],
      given_name: user_info[:given_name],
      family_name: user_info[:family_name],
      email_france_connect: user_info[:email],
      birthdate: user_info[:birthdate],
      birthplace: user_info[:birthplace],
      france_connect_particulier_id: user_info[:sub]
    )
```

par :

```ruby
    fci = FranceConnectInformation.new(
      gender: user_info[:gender],
      given_name: user_info[:given_name],
      family_name: user_info[:family_name],
      email_france_connect: user_info[:email],
      birthdate: user_info[:birthdate],
      birthplace: user_info[:birthplace],
      france_connect_particulier_id: user_info[:sub],
      provider: provider # pf: fournisseur d'identité, affiché sur la page profil
    )
```

Puis, dans `find_or_retrieve_user_informations`, après la ligne `fci.trusted_email_assertion = fetched_fci.trusted_email_assertion`, ajouter le backfill :

```ruby
    # pf: renseigne le provider sur la FCI ; backfill des anciennes lignes à la reconnexion.
    # data_changed? est faux si le provider était déjà à jour → pas de save inutile.
    fci.provider = provider
    fci.save! if fci.persisted? && fci.data_changed?
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/omni_auth_service_spec.rb -e "provider persisté"`
Expected: PASS (2 examples).

- [ ] **Step 5: Run the full service spec (non-régression)**

Run: `bundle exec rspec spec/services/omni_auth_service_spec.rb`
Expected: PASS (aucune régression sur `trusted_email_assertion?`).

- [ ] **Step 6: Commit**

```bash
git add app/services/omni_auth_service.rb spec/services/omni_auth_service_spec.rb
git commit -m "feat(pf): OmniAuthService pose et backfill le provider sur la FCI"
```

---

### Task 3: FranceConnectService — provider `particulier` à la création et backfill

**Files:**
- Modify: `app/services/france_connect_service.rb` (`find_or_retrieve_france_connect_information`, `retrieve_user_informations`)
- Test: `spec/services/france_connect_service_spec.rb`

**Interfaces:**
- Consumes: `FranceConnectInformation#provider=` (Task 1).
- Produces: à l'issue de `FranceConnectService.find_or_retrieve_france_connect_information(code, nonce)`, la FCI retournée a `provider == 'particulier'`, et une FCI persistée sans provider est mise à jour en base.

- [ ] **Step 1: Write the failing test**

Ajouter dans `spec/services/france_connect_service_spec.rb`, dans le `describe '.retrieve_user_informations'` (qui stubbe déjà `access_token`/`user_info`) ou juste après, un contexte dédié. Réutiliser le stub existant du fichier :

```ruby
describe 'provider particulier' do
  let(:code) { 'code' }
  let(:nonce) { 'nonce' }
  let(:user_info) { double('user_info', raw_attributes: { sub: 'sub-fc-1', email: 'a@b.fr' }) }

  before do
    access_token = instance_double('OpenIDConnect::AccessToken')
    allow_any_instance_of(OpenIDConnect::Client).to receive(:access_token!).and_return(access_token)
    allow(access_token).to receive(:userinfo!).and_return(user_info)
    allow(access_token).to receive(:id_token).and_return('id_token')
    allow(OpenIDConnect::ResponseObject::IdToken).to receive(:decode).and_return(double(verify!: true))
    stub_const('FRANCE_CONNECT', identifier: 'identifier', jwks: 'jwks')
  end

  it 'positionne provider=particulier sur une nouvelle FCI' do
    fci, _id_token = described_class.find_or_retrieve_france_connect_information(code, nonce)
    expect(fci.provider).to eq('particulier')
  end

  context 'FCI existante sans provider' do
    let!(:existing) { create(:france_connect_information, france_connect_particulier_id: 'sub-fc-1', user: create(:user)) }

    it 'backfill provider=particulier et persiste' do
      fci, _id_token = described_class.find_or_retrieve_france_connect_information(code, nonce)
      expect(fci.id).to eq(existing.id)
      expect(existing.reload.provider).to eq('particulier')
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/services/france_connect_service_spec.rb -e "provider particulier"`
Expected: FAIL — `provider` est `nil`.

- [ ] **Step 3: Write minimal implementation**

Dans `app/services/france_connect_service.rb`, méthode `retrieve_user_informations`, ajouter `provider: 'particulier'` au `FranceConnectInformation.new(...)` :

```ruby
    fci = FranceConnectInformation.new(
      gender: user_info[:gender],
      given_name: user_info[:given_name],
      family_name: user_info[:family_name],
      email_france_connect: user_info[:email],
      birthdate: user_info[:birthdate],
      birthplace: user_info[:birthplace],
      france_connect_particulier_id: user_info[:sub],
      provider: 'particulier' # pf: FranceConnect, affiché sur la page profil
    )
```

Puis dans `find_or_retrieve_france_connect_information`, remplacer :

```ruby
    fci_to_return = FranceConnectInformation.find_by(france_connect_particulier_id: fetched_fci[:france_connect_particulier_id]) || fetched_fci
    [fci_to_return, id_token]
```

par :

```ruby
    fci_to_return = FranceConnectInformation.find_by(france_connect_particulier_id: fetched_fci[:france_connect_particulier_id]) || fetched_fci
    # pf: renseigne/backfill le provider FranceConnect à la (re)connexion
    fci_to_return.provider = 'particulier'
    fci_to_return.save! if fci_to_return.persisted? && fci_to_return.data_changed?
    [fci_to_return, id_token]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/services/france_connect_service_spec.rb -e "provider particulier"`
Expected: PASS (2 examples).

- [ ] **Step 5: Run the full service spec (non-régression)**

Run: `bundle exec rspec spec/services/france_connect_service_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/services/france_connect_service.rb spec/services/france_connect_service_spec.rb
git commit -m "feat(pf): FranceConnectService pose et backfill provider=particulier"
```

---

### Task 4: Affichage du badge provider sur la page profil

**Files:**
- Modify: `app/views/users/profil/show.html.haml:81-82`
- Test: `spec/controllers/users/profil_controller_spec.rb`

**Interfaces:**
- Consumes: `FranceConnectInformation#provider` (Task 1) ; libellés i18n `omniauth.provider.{particulier,google,microsoft,tatou}` (existants).

- [ ] **Step 1: Write the failing test**

Ajouter dans `spec/controllers/users/profil_controller_spec.rb`, à l'intérieur de `describe 'GET #show'` (qui a déjà `render_views` et `sign_in(user)`) :

```ruby
context 'identités liées avec provider' do
  let!(:fci) do
    create(:france_connect_information, user: user, data: { 'provider' => 'tatou' })
  end

  before { post :show }

  it 'affiche le badge du provider' do
    expect(response.body).to include(I18n.t('omniauth.provider.tatou'))
  end
end

context 'identité liée sans provider (ancienne ligne)' do
  let!(:fci) { create(:france_connect_information, user: user) }

  before { post :show }

  it 'n’affiche aucun badge provider' do
    expect(response.body).not_to include('fr-badge--info')
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/controllers/users/profil_controller_spec.rb -e "provider"`
Expected: FAIL — le badge (libellé `Tātou` / classe `fr-badge--info`) n'est pas rendu.

- [ ] **Step 3: Write minimal implementation**

Dans `app/views/users/profil/show.html.haml`, remplacer le bloc (lignes 81-82) :

```haml
          %li
            #{fci.given_name} #{fci.family_name} (#{fci.email_france_connect})
```

par :

```haml
          %li
            - if fci.provider.present?
              %span.fr-badge.fr-badge--sm.fr-badge--info.fr-badge--no-icon.fr-mr-1w= t("omniauth.provider.#{fci.provider}")
            #{fci.given_name} #{fci.family_name} (#{fci.email_france_connect})
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bundle exec rspec spec/controllers/users/profil_controller_spec.rb -e "provider"`
Expected: PASS (2 examples).

- [ ] **Step 5: Run the full profil controller spec (non-régression)**

Run: `bundle exec rspec spec/controllers/users/profil_controller_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add app/views/users/profil/show.html.haml spec/controllers/users/profil_controller_spec.rb
git commit -m "feat(pf): badge du provider d'identité sur la page profil"
```

---

### Task 5: Vérification finale (lint + suite ciblée)

**Files:** aucun (vérification).

- [ ] **Step 1: Lint**

Run: `bundle exec rails lint`
Expected: aucune erreur (corriger via `bundle exec rubocop -A` si besoin, puis re-commit).

- [ ] **Step 2: Suite ciblée**

Run:
```bash
bundle exec rspec \
  spec/models/france_connect_information_spec.rb \
  spec/services/omni_auth_service_spec.rb \
  spec/services/france_connect_service_spec.rb \
  spec/controllers/users/profil_controller_spec.rb
```
Expected: tout PASS.

- [ ] **Step 3: Commit (si lint a modifié des fichiers)**

```bash
git add -A
git commit -m "chore(pf): lint badge provider identité"
```

---

## Notes de vérification manuelle

- Se connecter via Tātou puis Microsoft/Google → chaque identité liée affiche le bon badge sur `/profil`.
- Une identité liée avant ce changement (donc sans `data.provider`) n'affiche pas de badge, jusqu'à la prochaine reconnexion via le provider concerné (auto-réparation).
- Vérifier que le badge n'apparaît pas en double et reste lisible en responsive (badge DSFR `fr-badge--sm`).
