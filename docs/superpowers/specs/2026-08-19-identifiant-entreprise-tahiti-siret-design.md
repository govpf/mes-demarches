# Cohabitation numéro Tahiti / SIRET dans l'identification d'entreprise

**Date** : 2026-08-19
**Statut** : design validé, prêt pour plan d'implémentation

## Contexte

`mes-demarches` s'appuie sur le référentiel i-taiete de l'ISPF pour identifier les
entreprises polynésiennes par leur numéro Tahiti. Des identifiants d'accès à
**API Entreprise** (`entreprise.api.gouv.fr`) viennent d'être obtenus, ce qui ouvre
l'accès aux SIRET métropolitains.

L'objectif est que la saisie d'un identifiant d'entreprise — dans un champ SIRET
comme à l'entrée d'une démarche — fonctionne indifféremment avec un numéro Tahiti
ou un SIRET, tant sur la mécanique de recherche que sur les libellés.

## État des lieux

### La mécanique existe déjà, mais divergente

L'aiguillage par longueur est en place : 6-8 caractères déclenchent une liste de
candidats ISPF, 9 caractères passent par `PfEtablissementAdapter`, plus de 9
caractères par `EtablissementAdapter` (upstream). `SiretValidator` accepte déjà
les trois formats, et `ApiEntrepriseTokenConcern` dispose d'un fallback
`ENV['API_ENTREPRISE_KEY']`.

Le problème est que la règle « ce numéro est-il du Tahiti ou du SIRET ? » est
réimplémentée dans **sept fichiers**, avec **quatorze comparaisons de longueur**
qui ne disent pas la même chose :

| Site | Tahiti complet | Tahiti partiel | SIRET |
| --- | --- | --- | --- |
| `SiretValidator` | `== 9` | `== 6` seulement | `== 14` |
| `Champs::SiretChamp#ready_for_external_call?` | `6..9` | `6..9` | `== 14` + Luhn |
| `Champs::SiretChamp#fetch_external_data` | — | `between?(6, 8)` | — |
| `APIEntrepriseService.create_etablissement` | `== 9` | `< 9` → nil | `> 9` |
| `APIEntrepriseService#update_etablissement_from_degraded_mode` | `6..9` | — | `> 9` |
| `Users::DossiersController#update_siret` | — | `< 9` | `== 14` |
| `EtablissementHelper#pretty_siret` | `== 9` | — | `== 14` |

Deux bugs découlent directement de ce tableau :

- **10 à 13 caractères** : `create_etablissement` route `> 9` vers l'adapter
  français. Un numéro de 11 chiffres part en appel API et revient en erreur
  réseau au lieu d'une erreur de format immédiate.
- **7 à 8 caractères** : `Champs::SiretChamp` les accepte (`6..9`) mais
  `SiretValidator` les rejette (`when 6` / `when 9` seulement). L'usager
  déclenche la recherche de candidats puis se fait invalider à la soumission.

### Les libellés ont bifurqué

Upstream a refait le bloc d'identité d'entreprise en ViewComponent
(`Dossiers::IdentiteEntrepriseComponent`), qui résout ses libellés via
`Etablissement.human_attribute_name` → `config/locales/models/etablissement/fr.yml`.
Le fork a récupéré le composant **mais a gardé l'ancienne vue en parallèle**.
Deux chemins de rendu coexistent donc en production :

| Chemin | Fichiers | Libellé affiché |
| --- | --- | --- |
| Composant upstream | `shared/dossiers/_demande.html.haml:63`, `champs_rows_show_component.html.haml:43` | **« SIRET »** (`activerecord.attributes.siret`, jamais traduit) |
| Ancienne vue PF | `shared/champs/siret/_show.html.haml`, `instructeurs/dossiers/print.html.haml` | **« Numéro TAHITI »** (en dur dans le HAML) |

Un instructeur lit « SIRET » sur la page demande d'un dossier et « Numéro TAHITI »
sur l'impression du même dossier. Le défaut d'homogénéité n'est pas une dérive
diffuse : c'est cette bifurcation précise.

Par ailleurs, sept vues portent le libellé **en dur dans le HAML**. Ces chaînes
sont d'origine upstream — le fork a substitué le texte sur place, d'où le conflit
à chaque merge.

### Le validateur masque une gem

| | Upstream | Fork PF |
| --- | --- | --- |
| Gemfile | `gem 'siret_validator', github: "CodeursenLiberte/siret_validator", ref: "ba421bb"` | **retirée** (Gemfile et Gemfile.lock) |
| Validateur | fourni par la gem | `app/validators/siret_validator.rb`, **même nom de classe** |

Le fork substitue une gem par une classe locale homonyme. Les 2 call sites
(`Service`, `Siret`) continuent de fonctionner sans modification, mais rien ne
signale ce shadowing hors d'un commentaire.

Le Gemfile est touché par presque chaque release upstream. Le jour où un conflit
Gemfile est résolu en faveur d'upstream — ce que la doc du projet recommande par
défaut — la ligne revient et deux définitions de `SiretValidator` coexistent. La
gem étant chargée au boot par `Bundler.require`, la constante existe avant que
Zeitwerk ne pose ses autoloads : le cas le plus probable est que
`app/validators/siret_validator.rb` soit **purement ignoré** et le validateur PF
silencieusement désactivé, rejetant alors tous les numéros Tahiti sans la moindre
erreur au boot.

Enfin, `spec/models/siret_spec.rb` est identique à la version upstream : ses sept
contextes ne testent que le SIRET français. **Aucun cas Tahiti.** La moitié PF du
validateur, c'est-à-dire sa raison d'être, n'a jamais été testée directement — ce
qui explique que la divergence sur les 7-8 caractères ait pu s'installer.

## Décisions de cadrage

| Question | Décision |
| --- | --- |
| Nature des identifiants | Jeton **API Entreprise** (`entreprise.api.gouv.fr`) → la tuyauterie upstream est réutilisable telle quelle |
| Portée | **Globale**, sans configuration par démarche |
| Libellés de saisie | **Libellé neutre unique**, les deux formats expliqués à égalité |
| Libellés de restitution | **Terme stable « numéro Tahiti ou SIRET »**, piloté par les locales seules |
| Jobs d'enrichissement | **Actifs uniquement pour les SIRET à 14 chiffres** |
| Exports, colonnes, GraphQL | **Hors périmètre** — ne pas casser les scripts des instructeurs |

## Architecture

### 1. Value object `IdentifiantEntreprise`

`app/models/identifiant_entreprise.rb` — objet immuable, sans persistance.

```ruby
class IdentifiantEntreprise
  TAHITI_PARTIEL = /\A[0-9A-Z]\d{5,7}\z/  # 6 à 8 car. : G33972, G339720, G3397200
  TAHITI_COMPLET = /\A[0-9A-Z]\d{8}\z/    # 9 car.     : G33972001
  SIRET          = /\A\d{14}\z/           # 14 chiffres

  # Les trois expressions sont mutuellement exclusives par construction :
  # elles n'acceptent pas les mêmes longueurs.

  def self.parse(saisie) # normalise espaces, tirets, casse

  # --- nature : les trois prédicats sont mutuellement exclusifs ---
  def tahiti_partiel?    # 6 à 8 car. → peut désigner plusieurs établissements
  def tahiti_complet?    # 9 car.     → désigne un établissement unique
  def siret?             # 14 chiffres + Luhn (exception La Poste)

  # --- dérivés ---
  def tahiti?            # tahiti_partiel? || tahiti_complet? → relève de l'ISPF
  def valide?            # tahiti? || siret?
  def erreur             # :longueur | :checksum | nil
  def adapter_klass      # PfEtablissementAdapter | EtablissementAdapter
  def source             # :ispf | :api_entreprise
  def i18n_key           # :tahiti | :siret
  def format_lisible     # "G33972-001" ou "130 005 820 00019"
  def annuaire_url       # ispf.pf/rte ou annuaire-entreprises.data.gouv.fr
end
```

Deux règles tranchées définitivement :

- **10 à 13 caractères → invalide.** L'erreur de format est rendue immédiatement,
  sans appel API.
- **7 à 8 caractères → Tahiti partiel valide.** Une seule réponse pour tous les
  sites. Les 6 caractères (préfixe entreprise seul) et les 7-8 caractères
  (établissement amorcé) relèvent du même traitement — liste de candidats — d'où
  un unique prédicat `tahiti_partiel?` pour les trois longueurs.

Le pendant TypeScript (`app/javascript/controllers/format_controller.ts`) reçoit
les mêmes expressions régulières, extraites dans un module partagé, pour que la
mise en forme à la frappe suive exactement la règle serveur.

Aucune migration : `Etablissement#siret` continue de stocker indifféremment 9 ou
14 caractères. Le value object se dérive de la valeur, il ne la double pas en base.

### 2. Validateur renommé

`IdentifiantEntrepriseValidator`, coquille qui délègue au value object :

```ruby
class IdentifiantEntrepriseValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    identifiant = IdentifiantEntreprise.parse(value)
    record.errors.add(attribute, identifiant.erreur) unless identifiant.valide?
  end
end
```

Deux call sites à changer (`app/models/service.rb:26`, `app/models/siret.rb:10`) :
`validates :siret, identifiant_entreprise: true`.

Après ce renommage, le retour de la gem `siret_validator` au Gemfile devient
**inoffensif** : elle définirait une classe que plus personne n'utilise. Le
conflit de merge récurrent perd son enjeu. C'est le même raisonnement que pour
les libellés : plutôt que défendre indéfiniment une divergence contre upstream,
on supprime la collision.

### 3. Terminologie

**Terme canonique** : « numéro Tahiti ou SIRET » — Tahiti en capitale initiale,
SIRET en capitales. Une seule casse, décidée une fois : le code mélange
aujourd'hui `TAHITI`, `Tahiti` et `tahiti` selon les fichiers, ce qui rend toute
recherche-remplacement incertaine.

Deux variantes contextuelles dérivées du value object :

- **Saisie** — on ne sait pas encore ce que l'usager va taper : terme complet et
  les deux annuaires cités à égalité.
- **Restitution** — on connaît la valeur : `i18n_key` donne `:tahiti` ou `:siret`.

**Mécanisme** : `config/custom_locales/` existe déjà, est vide, et
`config/application.rb:41` le charge **après** `config/locales/**`. I18n fait un
deep-merge où le dernier chargé gagne. Toutes les surcharges de terminologie PF y
vont, et **on cesse de patcher les fichiers de locales upstream** :

```yaml
# config/custom_locales/entreprise.fr.yml
fr:
  activerecord:
    attributes:
      siret: "Numéro Tahiti ou SIRET"
      siret_siege_social: "Numéro Tahiti ou SIRET du siège social"
```

Quand upstream réécrit `config/locales/fr.yml`, le merge passe sans conflit *et*
notre terme gagne quand même. Aujourd'hui c'est l'inverse.

**Vérifié** : les colonnes du tableau instructeur et les exports ne passent pas
par `human_attribute_name` — ils lisent `config/locales/models/procedure_presentation/fr.yml`.
La surcharge ne les touche donc pas, conformément au périmètre décidé.

**Convergence** : là où upstream a un ViewComponent, on l'adopte et on supprime
l'ancienne vue PF plutôt que d'externaliser ses chaînes en dur — upstream est en
train de supprimer cette vue, l'améliorer ne servirait à rien.

### 4. Aiguillage API et jobs

**Le garde des jobs.** `APIEntrepriseService.perform_later_fetch_jobs`
(`app/services/api_entreprise_service.rb:124`) ne lance rien tant qu'aucun jeton
n'est configuré. Comme `ApiEntrepriseTokenConcern` retombe sur
`ENV['API_ENTREPRISE_KEY']`, **poser le jeton lève ce garde pour toutes les
démarches d'un coup**, y compris sur les établissements Tahiti : les 9 jobs
français partiraient interroger l'API gouv avec `G33972001`. C'est le point le
plus risqué du chantier, et il se déclenche à la seconde où la variable est posée.

Le garde devient une question de nature du numéro :

```ruby
identifiant = IdentifiantEntreprise.parse(etablissement.siret)

# EtablissementJob sait déjà router les deux sources (il appelle
# update_etablissement_from_degraded_mode, qui dispatche) → inconditionnel
jobs = [APIEntreprise::EtablissementJob] if etablissement.as_degraded_mode?
# les 9 autres sont strictement français
jobs += FRENCH_ONLY_JOBS if identifiant.siret?
```

Le garde sur le jeton reste, en second rideau.

**Les sondes de santé.** `service_unavailable_error?(error, target: :insee)`
appelle `api_insee_up?`, qui pointe en dur sur l'API ISPF. Un SIRET français qui
échoue est diagnostiqué avec la santé d'i-taiete ; inversement, si i-taiete tombe
pendant qu'API Entreprise va bien, un dossier SIRET bascule à tort en mode
dégradé. `fr_api_insee_up?` existe déjà dans le même fichier (ligne 147) et pinge
`entreprise.api.gouv.fr/ping/insee/sirene` : elle n'est appelée nulle part. Il
suffit de router selon `identifiant.siret?`, les quatre appelants
(`app/models/champs/siret_champ.rb:64`, `app/controllers/users/dossiers_controller.rb:258`
et `:620`) transmettant le value object qu'ils ont déjà en main.

**Les trois sites de routage.** `create_etablissement`,
`update_etablissement_from_degraded_mode` et `update_siret` cessent de compter
des caractères :

| Cas | Aujourd'hui | Après |
| --- | --- | --- |
| Tahiti partiel (6-8) | `< 9` / `between?(6,8)` / `>= 6 && <= 9` selon le site | `tahiti_partiel?` → candidats ISPF |
| Tahiti complet (9) | `== 9` | `tahiti_complet?` → `PfEtablissementAdapter` |
| SIRET (14) | `> 9` | `siret?` → `EtablissementAdapter` + `EntrepriseAdapter` |
| 10-13 caractères | `> 9` → appel API | `!valide?` → erreur de format immédiate |

La quatrième ligne disparaît sans code dédié, simplement parce que le routage
passe par un objet qui connaît la règle complète.

**Deux modes dégradés, pas un.** Avec deux fournisseurs, « l'API est en panne »
n'a plus de sens univoque : ISPF peut tomber sans qu'API Entreprise bronche. Le
value object permet à `update_etablissement_from_degraded_mode` de réessayer
auprès de la bonne source — ce qu'elle fait déjà par accident, et qui devient
explicite et testable. Un cas reste traité comme aujourd'hui : un établissement
Tahiti créé en mode dégradé alors que le numéro était **partiel** ne peut pas
être auto-complété ; l'usager repasse par la sélection manuelle.

**Le lien annuaire.** `DossierHelper#annuaire_link` (`app/helpers/dossier_helper.rb:229`)
construit `ispf.pf/rte/attestation/#{siret.first(6)}/#{siret.last(3)}` sans
discriminer : pour un SIRET à 14 chiffres, il produit une URL ISPF avec les 6
premiers et 3 derniers chiffres d'un numéro français. Lien mort, silencieux. Il
devient `identifiant.annuaire_url`.

## Tests

L'infrastructure existe : `spec/fixtures/files/api_entreprise/etablissements.json`
et `entreprises.json`, les stubs WebMock sur `entreprise.api.gouv.fr`
(`spec/services/api_entreprise_service_spec.rb:19-21`), et
`spec/models/champs/siret_champ_spec.rb` couvre déjà les deux formats en
parallèle. On construit dessus.

### Table de vérité du value object

`spec/models/identifiant_entreprise_spec.rb`, piloté par les données :

| Saisie | Attendu |
| --- | --- |
| `G33972` | tahiti partiel, ISPF, valide |
| `002253` | tahiti partiel (purement numérique) |
| `G33972001`, `G33972-001`, `g33972 001` | tahiti complet, même normalisation |
| `1234567`, `12345678` | tahiti partiel 7-8 car., **valide** |
| `13000582000019` | SIRET, API Entreprise, Luhn OK |
| `35600000000048` | SIRET La Poste, Luhn contourné |
| `13000582000018` | SIRET, erreur `:checksum` |
| `12345678901` | **invalide `:longueur`** — ne part pas en appel API |
| `""`, `nil`, `"abc"` | invalide |

Ce test remplace les quatorze comparaisons de longueur dispersées. Il doit rester
lisible comme une spécification : qui se demande « un numéro de 8 caractères,
est-ce valide ? » lit ce tableau, pas le code.

`spec/models/siret_spec.rb` gagne par ailleurs les contextes Tahiti qui lui
manquent depuis l'origine.

### Garde des jobs

La régression la plus coûteuse. Dans `api_entreprise_service_spec.rb`, avec
`ENV['API_ENTREPRISE_KEY']` **posé** — la condition de production qui n'existait
pas jusqu'ici :

| Cas | Attendu |
| --- | --- |
| établissement Tahiti (9 car.) | aucun des 9 jobs français enfilé |
| établissement Tahiti en dégradé | `EtablissementJob` seul |
| SIRET (14 car.) | les 10 jobs enfilés |
| sans jeton | aucun job, quel que soit le format |

Le spec existant (ligne 94, `api_entreprise_token: nil`) devient le quatrième cas.

### Chaînes de bout en bout

L'historique du projet montre que les bugs se logent dans le déclenchement, pas
dans le calcul. Trois scénarios dans `spec/system/users/` :

1. **Dépôt avec un SIRET français** — saisie à l'entrée d'une démarche, mise en
   forme JS à la frappe, résolution, bloc identité, poursuite du dossier. Vérifie
   que le libellé est « SIRET » et que le lien annuaire pointe vers
   `annuaire-entreprises.data.gouv.fr`.
2. **Dépôt avec un numéro Tahiti partiel** — le parcours existant (liste de
   candidats, sélection) ne doit pas régresser. C'est le chemin le plus utilisé
   en PF, et celui que le refactor du routage touche le plus.
3. **Bascule d'un format à l'autre dans un champ SIRET** — l'usager saisit un
   numéro Tahiti, valide, puis le remplace par un SIRET. Vérifie que
   `after_reset_external_data` nettoie l'ancien établissement et que la **cascade
   des formules** se redéclenche (`refresh_formulas_after` dans
   `update_external_data!`).

Le scénario 3 est non négociable : les deux premiers valident une fonctionnalité,
le troisième valide une interaction entre deux sous-systèmes qui ne se
connaissent pas.

### Gardes de terminologie

`spec/i18n/terminologie_entreprise_spec.rb`, deux vérifications :

1. **Terminologie** — chaque clé sensible déclarée contient le terme canonique ou
   une variante autorisée. Une réintroduction de « SIRET » seul par upstream fait
   rougir le test au lieu de passer inaperçue.
2. **Overrides orphelins** — chaque clé présente dans `custom_locales/` existe
   dans `config/locales/`. Quand upstream renomme ou supprime une clé, notre
   surcharge cesse silencieusement de s'appliquer ; ce test la transforme en
   échec explicite.

Ces deux specs ne testent pas du code, ils testent une **discipline**. C'est
assumé : leur rôle est de faire échouer la CI au prochain merge upstream plutôt
que de laisser une régression de libellé partir en production.

## Séquencement

Poser `API_ENTREPRISE_KEY` en production **est en soi un changement de
comportement** : le garde de `perform_later_fetch_jobs` tombe. L'ordre n'est donc
pas négociable — le garde doit être déployé **avant** la variable.

| Étape | Branche | Contenu | Charge |
| --- | --- | --- | --- |
| PR 1 — Socle | `feature/identifiant-entreprise-value-object` | Value object, validateur renommé, 2 call sites, table de vérité, contextes Tahiti de `siret_spec` | 1 à 1,5 j |
| PR 2 — Garde des jobs | `fix/api-entreprise-jobs-guard` | Garde par nature de numéro, routage des sondes de santé | 0,5 j |
| **⚡ Pose de `API_ENTREPRISE_KEY`** | — | Après déploiement de PR 2 | — |
| PR 3 — Routage unifié | `feature/routage-identifiant-entreprise` | `create_etablissement`, mode dégradé, `update_siret`, `annuaire_link`, `pretty_siret`, `format_controller.ts`, 3 specs système | 1,5 à 2 j |
| PR 4 — Terminologie | `feature/terminologie-identifiant-entreprise` | `custom_locales`, convergence composants upstream, 2 specs i18n | 1,5 à 2 j |
| PR 5 — i18n upstream | hors chemin critique | Externalisation des chaînes en dur restantes | 0,5 j |
| | | | **~5 à 6,5 j** |

À la pose de la variable, **le SIRET français fonctionne déjà de bout en bout** :
`update_siret` route déjà `> 9` vers `EtablissementAdapter`, le champ SIRET
accepte déjà 14 caractères avec Luhn. Il ne manquait que le jeton. La valeur
métier est donc livrée après 2 PR sur 4 ; le reste est du durcissement et de la
cohérence.

**PR 5** concerne les deux vues qu'upstream n'a pas migrées
(`app/views/users/dossiers/etablissement.html.haml`,
`app/views/administrateurs/services/_form.html.haml`), qui portent du français en
dur sans clés de locale. L'argument upstream tient sans rien devoir à la
Polynésie : un usager en locale anglaise y voit du français alors que le dépôt
contient les traductions. À ouvrir **avant** d'externaliser localement, pour que
les noms de clés soient fixés par la revue upstream et qu'on ne se crée pas un
conflit avec sa propre contribution.

Ce qui ne part jamais upstream : le terme « numéro Tahiti ou SIRET », le contenu
de `custom_locales/`, le value object.

## Rollback

Aucune migration, aucune donnée transformée. Retirer `API_ENTREPRISE_KEY` ramène
exactement au comportement actuel — les établissements Tahiti déjà créés ne
dépendent d'aucun élément de ce chantier.

## Hors périmètre

- **Exports, colonnes du tableau instructeur, champ GraphQL `siret`** : inchangés,
  pour ne pas casser les scripts et tableaux croisés des instructeurs.
- **Configuration par démarche** : la portée est globale. Si des instructeurs de
  démarches strictement locales remontent des dossiers métropolitains hors sujet,
  un garde-fou par démarche pourra être ajouté ensuite.
- **`Cron::BackfillSiretDegradedModeJob`** : tourne toutes les 2 heures sur tous
  les établissements avec `adresse: nil` et porte un `TODO: remove this job in a
  few days` depuis son introduction. Il ne déclenche pas de jobs français (il
  appelle `update_etablissement_from_degraded_mode`, qui dispatche correctement),
  donc il n'est pas un risque pour ce chantier. Mais en PF, où beaucoup
  d'établissements ISPF n'ont pas d'adresse, il martèle probablement l'API
  i-taiete en permanence pour rien. À regarder dans un autre chantier.
