# Suppression des providers d'authentification obsolètes : yahoo, sipf, facebook

**Date** : 2026-07-20
**Nature** : nettoyage de code auth-critique
**Statut** : yahoo, sipf et facebook confirmés obsolètes côté PF

## Contexte

Trois fournisseurs d'identité OpenID ne sont plus utilisés en Polynésie française :

- **`yahoo`** : connexion via compte Yahoo (scope `sdpp-w`), conditionnée à
  `email_verified`. Abandonné.
- **`sipf`** : « Agent de l'administration » via Keycloak (identité forte). Remplacé
  par Microsoft `@administration.gov.pf` via ProConnect
  (cf. `app/controllers/concerns/pro_connect_session_concern.rb`).
- **`facebook`** : déjà non fonctionnel — absent de `OmniAuthService::PROVIDERS`,
  des routes et de `config/initializers/pf_omniauth_providers.rb`. Ne subsistent que
  des reliquats (valeur d'enum, `secrets.yml`, `env.example`, libellés i18n).

Providers conservés après nettoyage : `google`, `microsoft`, `tatou`,
`particulier` (FranceConnect).

## Objectif

Retirer tout le code, la configuration et les tests liés aux providers `yahoo` et
`sipf`, sans casser les comptes existants ni le modèle de confiance des providers
restants.

## Portée — éléments à supprimer

### Service
- `app/services/omni_auth_service.rb`
  - `PROVIDERS` : retirer `'yahoo'`, `'sipf'` → `['google', 'microsoft', 'tatou']`
  - `STRONG_IDENTITY_PROVIDERS` : retirer `'sipf'` → `['tatou']`
  - `authorization_uri` : retirer la branche scope spécifique `yahoo`
    (`provider == 'yahoo' ? [:'sdpp-w'] : [:profile, :email]`) → `[:profile, :email]`
  - Commentaires mentionnant yahoo/sipf à ajuster

### Modèle
- `app/models/user.rb` : retirer les valeurs `yahoo: 'yahoo'`, `sipf: 'sipf'` et
  `facebook: 'facebook'` de l'enum `loged_in_with_france_connect` **après** migration
  des données (voir plus bas)

### Contrôleurs
- `app/controllers/users/sessions_controller.rb:77` : la branche logout
  `when ...fetch(:sipf), ...fetch(:tatou)` — retirer `sipf`, garder `tatou`
  (vérifier que le comportement logout tatou reste correct)

### Configuration
- `config/routes.rb` : retirer `yahoo` et `sipf` des 6 contraintes de route
  `constraints: { provider => /google|microsoft|yahoo|tatou|sipf/ }`
  → `/google|microsoft|tatou/`
- `config/initializers/pf_omniauth_providers.rb` : blocs `'yahoo'` et `'sipf'`
  (pas de bloc `facebook` ici)
- `config/secrets.yml` : blocs `yahoo:`, `sipf:` et `facebook:`
- `config/env.example` : `YAHOO_CLIENT_ID`, `YAHOO_CLIENT_SECRET`,
  `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`

### Vues et i18n
- `config/locales/views/shared/fr.yml:24-25` et `en.yml:23-25` : entrées
  `yahoo: "Yahoo!"` et `sipf: "Agent de l'administration"` / `"Administration officer"`
- `config/locales/fr.yml:1162` et `en.yml:1082` : entrée `facebook: Facebook` sous
  `omniauth.provider`
- Vérifier `app/views/users/sessions/new.html.haml` et le partiel `_social_login`
  (le commentaire ligne 12 mentionnant sipf/tatou) — retirer les liens yahoo/sipf
  (facebook n'y figure déjà plus)

### Tests
- `spec/services/omni_auth_service_spec.rb` : contextes `google / yahoo` et
  `%w[tatou sipf]` (strong providers) → retirer yahoo/sipf
- `spec/controllers/users/sessions_controller_spec.rb:169-174` : contexte
  « connected with sipf keycloak » → supprimer
- `spec/views/commencer/show.html.haml_spec.rb` : blocs `YAHOO_CLIENT_ID`,
  `SIPF_CLIENT_ID`
- `spec/views/users/sessions/new.html.haml_spec.rb` : blocs `YAHOO_CLIENT_ID`,
  `SIPF_CLIENT_ID`

## ⚠️ Faux positifs — à NE PAS toucher

Ces occurrences matchent `yahoo`/`sipf` mais n'ont aucun rapport avec les
providers d'authentification :

- `app/lib/email_checker.rb` : `yahoo.fr`, `yahoo.com`, etc. = **domaines email**
  connus (liste anti-typo). Conserver.
- `config/initializers/contacts.rb` : « SIPf » = **Service Informatique de la
  Polynésie française** (l'organisation). Conserver.
- `spec/fixtures/cassettes/numero_dn_check.yml` : `sipf` = **username de l'API
  CPS** (numéro DN). Conserver.
- `spec/system/users/sign_up_spec.rb` : `bidou@yahoo.fr`/`.rf` = email de test.
  Conserver.

## Migration de données (enum)

Retirer une valeur d'enum casse le chargement des `User` qui la portent encore.

**Étape préalable obligatoire** : migrer les lignes existantes avant/pendant la
suppression de l'enum.

```ruby
# migration
def up
  execute(<<~SQL)
    UPDATE users
    SET loged_in_with_france_connect = NULL
    WHERE loged_in_with_france_connect IN ('sipf', 'yahoo', 'facebook')
  SQL
end
```

`loged_in_with_france_connect` étant un marqueur « dernière connexion » (déjà remis
à `nil` à la déconnexion), le passer à `NULL` est sans effet fonctionnel : ces
utilisateurs le repositionneront à leur prochaine connexion via un provider valide.

> Note migration/maintenance-task : cette mise à `NULL` doit se faire dans la
> migration elle-même (pas une maintenance task séparée), pour éviter le piège
> multi-releases documenté dans CLAUDE.md.

## Vérification prod recommandée (avant merge)

Bien que yahoo/sipf soient confirmés obsolètes, compter les lignes impactées pour
dimensionner et documenter la migration :

```sql
SELECT loged_in_with_france_connect, COUNT(*)
FROM users
WHERE loged_in_with_france_connect IN ('sipf', 'yahoo', 'facebook')
GROUP BY 1;
```

## Sécurité

- Retirer `sipf` de `STRONG_IDENTITY_PROVIDERS` **réduit** la surface de confiance
  (aucun assouplissement). Vérifier qu'aucun test/flux ne suppose `sipf` digne de
  confiance après coup.
- Aucun impact sur le modèle de confiance des providers conservés
  (`tatou` reste identité forte ; `google`/`microsoft` inchangés).

## Tests de non-régression

- `bundle exec rspec spec/services/omni_auth_service_spec.rb`
- `bundle exec rspec spec/controllers/users/sessions_controller_spec.rb`
- `bundle exec rspec spec/controllers/omniauth_controller_spec.rb`
- Vérifier que la page de connexion n'affiche plus yahoo/sipf et que
  google/microsoft/tatou/FranceConnect fonctionnent toujours.
- `bundle exec rails lint`

## Hors périmètre

- Feature « badge provider sur le profil » (spec séparé
  `2026-07-19-provider-identite-profil-design.md`).
- Suppression de la colonne `loged_in_with_france_connect` elle-même (on ne retire
  que deux valeurs de l'enum).
