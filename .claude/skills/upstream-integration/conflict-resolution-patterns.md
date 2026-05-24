# Résolution de conflits par type de fichier

**Règle d'or : aucun `git checkout --theirs` ou `--ours` global.** Chaque conflit se résout fichier par fichier, après lecture du contexte.

## Méta-règle de décision

Quand un conflit apparaît :

1. **Chercher les tags `# pf:`** dans le fichier (`grep -n "pf:" <fichier>`) — avant ET après merge
2. **Identifier la catégorie** (voir sections ci-dessous)
3. **Appliquer le pattern de la catégorie**
4. **Si le doute persiste → STOP et demander à l'utilisateur**

Une absence de tag `# pf:` ne signifie pas absence de spécificité PF. Cas vérifié : `4384704e24` "restaurer code PF pour attestation v2 dans tiptap_service.rb" — aucun tag, tout le code PF avait disparu après merge.

## Catégorie 1 — Mailers et templates email

### Risque
- Domaine d'envoi (`From`) écrasé par upstream → mails sortent depuis `demarches.numerique.gouv.fr` au lieu de `demarches.pf` (cas `78aefa3324`)
- Méthode mailer supprimée upstream mais appelée côté PF (cas `b53b91fdb2`)
- Template email écrasé sans tag `# pf:` (cas `f3e61b2752` "fix: re add mail template lost during merge")

### Check obligatoire AVANT de prendre upstream

```bash
# Pour chaque mailer en conflit
git diff $DERNIER_TAG_PF..$TARGET_TAG -- app/mailers/ app/views/*_mailer/

# Vérifier les configurations de domaine
git diff $DERNIER_TAG_PF..$TARGET_TAG -- config/initializers/ | grep -iE "host|domain|mail"

# Vérifier les méthodes supprimées
git diff $DERNIER_TAG_PF..$TARGET_TAG -- app/mailers/ | grep "^-  def " | awk '{print $2}'
# Pour chaque méthode supprimée :
grep -rn "<method_name>" app/controllers/ app/services/ app/jobs/
```

### Pattern de résolution

- Si méthode supprimée upstream **est appelée** ailleurs en PF → la **garder** + tag `# pf:`
- Si `forced_domain == APP_HOST` ou logique de domaine → **vérifier sémantiquement** que la branche s'active bien dans le bon contexte (cas vu : branche upstream `elsif forced_domain == APP_HOST` matchait en PF par accident)
- Templates email : copier-coller upstream peut écraser le footer/header PF → résoudre manuellement en gardant les deux apports

## Catégorie 2 — Locales (`config/locales/*.fr.yml`)

### Risque
- `git checkout --theirs config/locales/` est l'anti-pattern le plus fréquent (cas `9bd77690be`, `772703e696`, `b1c2e29df2`)
- Écrasement de clés contenant "DTI", "GIP OKANTIS", "Numéro TAHITI", "DN", "Polynésie", "communes PF"
- Renommage de clés upstream non détecté → erreurs `translation missing` en runtime

### Check obligatoire

```bash
# Diff sémantique des locales
git diff $DERNIER_TAG_PF..$TARGET_TAG -- config/locales/*.fr.yml > /tmp/locale_diff.txt

# Mots-clés PF à scanner DANS le diff
grep -iE "tahiti|polyn[ée]sie|communes? PF|num[ée]ro DN|DTI|GIP|okantis|t[eé] fenua|CPS|SIPF|tatou" /tmp/locale_diff.txt
```

### Pattern de résolution

1. Pour chaque clé en conflit, lire les deux versions (HEAD et upstream)
2. Garder le **squelette upstream** (nouvelle hiérarchie, nouvelles clés)
3. **Réinsérer manuellement** les valeurs PF dans la nouvelle structure
4. Si une clé PF disparaît côté upstream mais reste référencée dans `app/views/` PF → garder la clé + tag `# pf:` dans un commentaire YAML
5. Ne JAMAIS lancer `git checkout --theirs config/locales/`

## Catégorie 3 — Migrations et maintenance tasks

### Risque
- **PG::CheckViolation** sur multi-release (cas PR #319 : `attestation_templates.kind`)
- MT intercalée entre deux migrations qui pose une contrainte
- `Maintenance Task` ajoutée sans `run_on_first_deploy` alors qu'elle est CRITIQUE

### Check obligatoire (en complément de [maintenance-task-decision.md](./maintenance-task-decision.md))

```bash
# Migrations qui posent des contraintes
git diff $DERNIER_TAG_PF..$TARGET_TAG --diff-filter=A --name-only -- db/migrate/ | while read f; do
  grep -lE "change_column_null|validate_check_constraint|add_check_constraint.*validate: true|add_index.*unique" "$f" 2>/dev/null
done

# MT de backfill intercalées
git diff $DERNIER_TAG_PF..$TARGET_TAG --diff-filter=A --name-only -- app/tasks/maintenance/ | grep -v concerns/ | while read f; do
  grep -lE "update_all|update!|where.*nil|backfill" "$f" 2>/dev/null
done

# Croisement temporel : timestamps
# Migration 20250908* + MT t20250908* + Migration 20250930* = pattern dangereux
```

### Pattern de résolution

Si MT intercalée détectée :

```ruby
# Option A — Intégrer le backfill dans la migration de contrainte
def up
  # pf: backfill avant contrainte — upstream utilise une MT intercalée entre 2 releases
  safety_assured { execute("UPDATE table SET col = 'default' WHERE col IS NULL") }
  add_check_constraint :table, "col IS NOT NULL", name: "constraint_name", validate: false
end
```

Voir aussi [maintenance-task-decision.md](./maintenance-task-decision.md).

## Catégorie 4 — Schéma GraphQL (`schema.graphql`, `app/graphql/`)

### Risque
- Régénération partielle du schéma → types PF orphelins
- Nouveau type upstream conflictuel avec extension PF
- Mutation PF supprimée par accident lors du merge

### Check obligatoire

```bash
# Lister les types PF
grep -rln "Polynesie\|TeFenua\|Visa\|Referentiel" app/graphql/types/

# Après merge :
bin/rails graphql:schema:dump
git diff schema.graphql
# → vérifier qu'aucun type PF n'a disparu
```

### Pattern de résolution

1. **TOUJOURS régénérer** : `bin/rails graphql:schema:dump`
2. Si un type PF a disparu du schema → chercher pourquoi (résolution conflit qui a supprimé un `field :` ou un `implements`)
3. Tester : `bundle exec rspec spec/controllers/api/v2/graphql_controller_spec.rb`

## Catégorie 5 — `Gemfile.lock`

### Risque
- Résolution `--ours` ou `--theirs` aveugle → gems PF perdues OU versions incohérentes (cas PR #314 : 2 fix consécutifs sur Gemfile.lock)
- Régénération qui bump des gems non voulues

### Pattern de résolution

```bash
# 1. Toujours résoudre Gemfile (pas Gemfile.lock) manuellement
# 2. Pour Gemfile.lock : régénérer
git checkout --ours Gemfile.lock  # base PF
bundle install  # met à jour selon le Gemfile résolu
git add Gemfile Gemfile.lock
# 3. Vérifier
bundle check
bundle outdated --groups | head -20
```

## Catégorie 6 — Champs PF natifs (`app/models/champs/referentiel_de_polynesie_champ.rb`, etc.)

### Risque
- Refactor upstream du cycle de vie du champ (`Champ#after_save`, `Champ#fork`, `Champ#clone`) → cascade PF cassée
- Renommage de méthode upstream non répliqué côté PF

### Fichiers 100% PF (à protéger absolument)

- `app/models/champs/referentiel_de_polynesie_champ.rb`
- `app/models/champs/visa_champ.rb`
- `app/models/champs/te_fenua_champ.rb`
- `app/graphql/types/champs/referentiel_de_polynesie_*`
- `app/components/dsfr/champ/referentiel_de_polynesie/`

### Pattern de résolution

- Ces fichiers ne devraient **jamais** être modifiés par upstream
- Si conflit → résoudre `--ours` (notre version) mais **vérifier les méthodes parentes** invoquées (super, callbacks parents)
- Lancer immédiatement les tests dédiés :
  ```bash
  bundle exec rspec spec/models/champs/referentiel_de_polynesie_champ_spec.rb \
                    spec/models/champs/visa_champ_spec.rb \
                    spec/models/champs/te_fenua_champ_spec.rb
  ```

## Catégorie 7 — Contrôleurs d'authentification

Voir [omniauth-franceconnect-checklist.md](./omniauth-franceconnect-checklist.md). Pattern majeur, traitement dédié.

## Catégorie 8 — Concerns de dossier (`dossier_*_concern.rb`)

### Risque
- Refactor upstream du cycle de vie dossier (clone, rebase, fork, autosave, merge_user_buffer_stream)
- Cascade des formules cassée silencieusement (CLAUDE.md → section "Cascade des formules" + mémoire `feedback_formula_system_tests`)

### Check obligatoire

```bash
# Fichiers à risque
for f in app/models/concerns/dossier_champs_concern.rb \
         app/models/concerns/dossier_rebase_concern.rb \
         app/models/concerns/dossier_clone_concern.rb \
         app/models/concerns/dossier_prefillable_concern.rb; do
  git diff $DERNIER_TAG_PF..$TARGET_TAG -- "$f" | head -50
done

# Si modif → audit cascade formule obligatoire
bundle exec rspec spec/models/champs/formule_cascade_audit_spec.rb
bundle exec rspec spec/models/concerns/dossier_clone_concern_spec.rb
```

### Pattern de résolution

1. Si modif upstream touche un sentier de modification de champ : **vérifier qu'un `dossier.refresh_formulas_after(champ)` est bien appelé** (cf. CLAUDE.md section "Cascade des formules")
2. Si un nouveau sentier est créé upstream : **ajouter explicitement** l'appel cascade + tag `# pf:`
3. Lancer le spec d'audit cascade en plus des tests classiques

## Catégorie 9 — Tests système (`spec/system/`)

### Risque
- Refactor upstream d'un sélecteur Capybara → tests system PF qui se basent dessus cassent
- Cherry-pick "empty" silencieux qui perd un fix Capybara (cas PR #256 `0e74d8afe4`)

### Pattern de résolution

- Tests system : **ne pas se contenter du diff** — lancer le test concrètement
- Si cherry-pick utilisé pour la PR : `git diff origin/<branche-source>` après cherry-pick pour repérer les commits "empty"

## Catégorie 10 — Fichiers neufs côté upstream qui n'existent pas en PF

### Pattern de résolution

- Lire le fichier upstream et vérifier qu'il n'introduit pas de comportement qui conflit avec une feature PF existante
- Ajouter sans modification (pas de tag `# pf:` nécessaire si pure addition upstream)
- Si le fichier doit être étendu PF (ex: nouveau provider à ajouter) → faire l'extension dans un commit séparé après le merge

## Catégorie 11 — Suppression de fichiers côté upstream

### Risque

- Suppression upstream d'un fichier que PF a étendu silencieusement
- Suppression upstream d'un mailer/service utilisé uniquement par OmniAuth (cas `acc868d20d`)

### Check obligatoire

```bash
# Lister les fichiers supprimés par upstream
git diff $DERNIER_TAG_PF..$TARGET_TAG --diff-filter=D --name-only

# Pour chaque fichier supprimé, chercher des usages PF
for f in <fichier_supprime>; do
  base=$(basename "$f" .rb)
  class_name=$(echo "$base" | sed 's/_\(.\)/\U\1/g' | sed 's/^\(.\)/\U\1/')
  grep -rn "$class_name\|$base" app/ config/ spec/ | grep -v "^Binary"
done
```

Si usages PF trouvés → garder le fichier + tag `# pf:` dans un commentaire d'entête.
