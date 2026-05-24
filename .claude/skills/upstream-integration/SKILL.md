---
name: upstream-integration
description: Use when creating a feature/bump-AAAA-MM-JJ PR that integrates one or more upstream releases from demarches-simplifiees.fr into mes-demarches (PF fork). Covers branch creation, merge, conflict resolution decisions, maintenance task arbitration, post-merge audit and PR submission.
---

# Intégration upstream — workflow guidé

## Principe fondamental

**Le skill guide, vérifie, et S'ARRÊTE à chaque décision importante.** Il ne merge pas en autonomie. À chaque point d'arrêt marqué `🛑 STOP`, attendre la validation manuelle avant de continuer.

## Pourquoi ce skill existe (statistique brutale)

Analyse des 15 dernières PRs `feature/bump-*` :

- **0 PR sur 15 sans fix post-merge** dans les 14 jours
- **Moyenne 21 commits de fix** par PR sur 14 jours
- Cas extrêmes : PR #323 (32 fix), PR #313 (20 fix), PR #320 (15 fix)
- **3 mois en prod** avec le bouton "envoyé" sans envoi réel d'email (cf. `b53b91fdb2` : omniauth_merge_confirmation supprimé côté FC sans répliquer)
- **100% des mails de cron quotidien** pointant vers le mauvais domaine pendant plusieurs jours (`78aefa3324`)

Le skill matérialise les checks qui auraient évité ces régressions.

## Les 4 invariants

1. **Base de comparaison = dernier tag PF, JAMAIS un tag upstream**
   ```bash
   DERNIER_TAG_PF=$(git tag -l "pf-*" | sort -V | tail -1)
   ```
2. **Aucun `git checkout --theirs <dir>` global** — résolution fichier par fichier, même pour `config/locales/`
3. **Si touche `france_connect/` → vérifier obligatoirement `omniauth/`** (cf. [omniauth-franceconnect-checklist.md](./omniauth-franceconnect-checklist.md))
4. **Toute nouvelle Maintenance Task → décision explicite auto-startup OU mention release notes** (cf. [maintenance-task-decision.md](./maintenance-task-decision.md))

## Workflow A→Z

### Étape 1 — Préparation et choix de la cible

```bash
git checkout devpf && git pull origin devpf
DERNIER_TAG_PF=$(git tag -l "pf-*" | sort -V | tail -1)
git fetch upstream --tags

# Lister releases upstream non intégrées depuis DERNIER_TAG_PF
git log $DERNIER_TAG_PF..upstream/main --oneline | head -30
```

**Décision : 1 release ou cumul ?**

Cumul possible **uniquement si** : pas de maintenance task de backfill intercalée entre deux migrations qui posent des contraintes (voir [conflict-resolution-patterns.md](./conflict-resolution-patterns.md) section migrations).

🛑 **STOP — Demander à l'utilisateur** : "X releases identifiées entre `$DERNIER_TAG_PF` et upstream. Cumul ou une par une ?" (utiliser AskUserQuestion).

### Étape 2 — Création de la branche

```bash
git checkout -b feature/bump-AAAA-MM-JJ-NN
```

Nommage : prendre la **dernière** release du cumul (ex: si on cumule `2025-04-16-01` à `2025-04-30-01`, nommer `feature/bump-2025-04-30-01`).

### Étape 3 — Pré-analyse AVANT merge (cruciale)

Identifier les zones de risque AVANT de lancer `git merge` :

```bash
TARGET_TAG="2025-MM-JJ-NN"  # release upstream cible

# 1. Volumétrie
git diff $DERNIER_TAG_PF..$TARGET_TAG --stat | tail -20

# 2. Zones critiques touchées
for zone in app/controllers/france_connect/ app/services/france_connect/ \
            app/controllers/omniauth_controller.rb \
            app/models/champ.rb app/models/type_de_champ.rb \
            app/services/formula_calculation_service.rb \
            app/models/concerns/dossier_champs_concern.rb \
            config/locales/ db/migrate/ app/tasks/maintenance/; do
  count=$(git diff $DERNIER_TAG_PF..$TARGET_TAG --name-only -- "$zone" 2>/dev/null | wc -l)
  [ "$count" -gt 0 ] && echo "⚠️  $zone : $count fichier(s)"
done

# 3. Nouvelles migrations et MT
git diff $DERNIER_TAG_PF..$TARGET_TAG --diff-filter=A --name-only -- db/migrate/ | sort
git diff $DERNIER_TAG_PF..$TARGET_TAG --diff-filter=A --name-only -- app/tasks/maintenance/ | grep -v concerns/
```

🛑 **STOP — Rapport de pré-analyse** : présenter à l'utilisateur les zones touchées + alertes. Si `france_connect/` touché, ouvrir d'office [omniauth-franceconnect-checklist.md](./omniauth-franceconnect-checklist.md).

### Étape 4 — Merge

```bash
git merge $TARGET_TAG
```

Pour les conflits qui sortent : suivre **strictement** [conflict-resolution-patterns.md](./conflict-resolution-patterns.md).

**Règle absolue : aucun `git checkout --theirs <dir>` global.** Chaque conflit est résolu individuellement.

🛑 **STOP — Liste des fichiers en conflit** : présenter la liste à l'utilisateur, classer par catégorie (locales / migrations / contrôleurs / mailers / etc.), et demander confirmation pour la stratégie par catégorie.

### Étape 5 — Résolution des conflits

Pour chaque fichier en conflit :

1. **Chercher les tags `# pf:`** : `grep -n "pf:" <fichier>` avant et après merge
2. **Identifier la catégorie** (mailer / locale / GraphQL / migration / formule / auth / etc.)
3. **Appliquer le pattern** correspondant dans [conflict-resolution-patterns.md](./conflict-resolution-patterns.md)
4. **Si fichier sans tag `# pf:`** mais code PF présent (cas `4384704e24` : `tiptap_service.rb` n'avait aucun tag mais contenait tout le code attestation v2 PF) → tag à ajouter, ne pas écraser

### Étape 6 — Décision Maintenance Tasks

Pour chaque MT nouvelle (filter `diff-filter=A` sur `app/tasks/maintenance/`) :

🛑 **STOP — Décision MT obligatoire**. Pour chaque MT : utiliser l'arbre de décision dans [maintenance-task-decision.md](./maintenance-task-decision.md). Trois issues possibles :
- **A** : décommenter `run_on_first_deploy` (backfill critique, contraintes NOT NULL liées)
- **B** : laisser commenté ET noter dans les release notes "passer manuellement la MT XXX après déploiement"
- **C** : intégrer le backfill directement dans une migration (cas multi-releases avec contrainte qui suit)

### Étape 7 — Audit post-merge AVANT commit

Suivre [post-merge-audit.md](./post-merge-audit.md). Au minimum :
- `bundle install` (vérifier Gemfile.lock cohérent)
- `bin/rails graphql:schema:dump` (vérifier régénération propre)
- Tests critiques PF :
  ```bash
  bundle exec rspec spec/models/champs/ spec/controllers/omniauth_controller_spec.rb \
                    spec/services/formula_calculation_service_spec.rb \
                    spec/models/champs/formule_cascade_audit_spec.rb
  ```
- Cohérence Ruby : `.ruby-version` vs `Dockerfile`

🛑 **STOP — Rapport d'audit** avant tout commit.

### Étape 8 — Commit et push

```bash
git add -p   # SURTOUT PAS git add -A : valider chaque hunk
git commit -m "$(cat <<'EOF'
chore(upstream): merge releases AAAA-MM-JJ à AAAA-MM-JJ

- Releases intégrées : [liste]
- Adaptations PF : [liste avec tags # pf: ajoutés]
- Maintenance tasks : [auto-startup / mention release notes]
EOF
)"
```

🛑 **STOP avant `git push` et avant `gh pr create`** : présenter le message de PR + checklist post-merge, attendre validation explicite.

### Étape 9 — Création PR

Le corps de la PR doit inclure :

```markdown
## Releases upstream intégrées

- AAAA-MM-JJ-NN (lien)
- ...

## Adaptations PF appliquées

- [Liste avec fichier + nature]

## Maintenance Tasks

- ✅ Auto : T20XXMMNN... (décommentage run_on_first_deploy)
- ⚠️  **Manuel après déploiement** : TXXX... — raison : [...]

## Checks post-merge

- [ ] Tests PF critiques OK
- [ ] omniauth/franceconnect audité (si applicable)
- [ ] Migrations multi-releases : pas de PG::CheckViolation potentiel
- [ ] Gemfile.lock régénéré proprement
- [ ] Schema GraphQL régénéré
```

## Top 10 fichiers à très haute surveillance (débiaisé)

Source : analyse des **219 commits "fix"** du mainteneur principal sur 9 mois, **filtrés pour ne garder que les fix upstream-related** (les fix de features PF natives en cours — formule, attestation v2, lexpol, te_fenua, numero_dn, notifications différées, referentiel_de_polynesie — sont **exclus** car non corrélés au merge upstream).

| # | Fichier / zone | Fix upstream-related | Pattern de régression |
|---|---|---|---|
| 1 | `app/controllers/omniauth_controller.rb` + spec | 5 | Symétrie FC↔OmniAuth (cf. [omniauth-franceconnect-checklist.md](./omniauth-franceconnect-checklist.md)) |
| 2 | `app/views/france_connect/**` + routes FC | 4 | Refactor naming upstream (notation `particulier`, partials password) |
| 3 | `config/locales/{fr.yml,en.yml,models/**,views/**}` | 6 | Vague de traductions divergentes ("adresse électronique", error_key, button_merge) |
| 4 | `app/mailers/application_mailer.rb` + `user_mailer.rb` | 1 | Branche `forced_domain == APP_HOST` qui matche par hasard en PF (cas `78aefa33`) — **gros impact** |
| 5 | `app/models/types_de_champ/lexpol_type_de_champ.rb` | 3 | Refonte interface TypeDeChamp upstream (orphelins, re-publish) |
| 6 | `app/models/champs/decimal_number_champ.rb` + numeric | 3 | Renommages upstream (min/max → min_number/max_number, double erreur regex) |
| 7 | `db/migrate/**` couplé à `app/tasks/maintenance/**` | 3 | MT intercalées multi-releases (cas PR #319 `attestation_templates.kind`) |
| 8 | `app/components/dsfr/champ/**` + `_champ.html.haml` | 2 | Descriptions, `legend_label`, doublons après refactor upstream |
| 9 | `app/components/.../etablissements_list_component.html.haml` | 2 | Logique PF auto-sélection SIRET 6→9 chiffres (Tahiti) cassée par modifs upstream du composant |
| 10 | `app/models/concerns/dossier_champs_concern.rb` | 2-3 | Refactor upstream forks→streams; risque cascade formule (ambigu mais à garder en surveillance) |

**Si l'un de ces fichiers est en conflit → audit renforcé obligatoire** (cf. [post-merge-audit.md](./post-merge-audit.md)).

### Fichiers à NE PAS confondre (features PF natives — exclus de la surveillance upstream)

Ces fichiers concentrent beaucoup de fix dans l'absolu, mais ces fix sont **liés au développement de features PF en cours** et **non à un merge upstream**. Ne pas se laisser piéger par le bruit.

- `app/services/formula_calculation_service.rb`, `app/lib/formula*`, `app/components/dsfr/champ/formule_*`, `app/models/champs/formule_champ.rb` (~45 fix PF-native sur 9 mois)
- `app/models/champs/referentiel_de_polynesie_champ.rb` (~10 fix natifs — bugs propres à la feature)
- Attestation v2 (templates, migration v1→v2, TiptapService, PieceJustificativePresentation) — ~15 fix natifs
- `app/models/champs/numero_dn_champ.rb` — ~5 fix natifs
- `app/models/notification.rb` (différée) — ~3 fix natifs
- Sentry guards génériques (`nil.email`, etc.) — ~10 fix réactifs (incidents prod), pas post-merge

**Le signal "fix dans les 14 jours après PR `feature/bump-*`" est trompeur** : 62% des fix maatinito sur 9 mois sont PF-native. Privilégier les indicateurs sémantiques (mots-clés "restore", "réapplique", "lost during merge", "conflit", "aligner", ajout de tag `# pf:`, réactivation de test).

## Red flags — STOP et investiguer

| Signal | Action |
|---|---|
| `git checkout --theirs config/locales/` proposé | ❌ STOP — résoudre fichier par fichier |
| Conflit dans `france_connect/` sans toucher `omniauth/` | ❌ STOP — ouvrir omniauth-franceconnect-checklist.md |
| Migration ajoute `validate_check_constraint` ou `change_column_null` | ❌ STOP — chercher MT de backfill intercalée |
| Plus de 5 releases dans le cumul | ⚠️ Risque PG::CheckViolation élevé, faire 2 PR |
| Une MT contient `update_all` ou `where(...).update!` sans `run_on_first_deploy` | ❌ STOP — arbre de décision MT |
| `Gemfile.lock` résolu en `--ours` ou `--theirs` | ⚠️ Régénérer obligatoirement via `bundle install` |
| Code PF identifié (mais sans tag `# pf:`) supprimé par upstream | ❌ STOP — restaurer + tag |

## Anti-patterns historiques (à NE PAS reproduire)

- **`f3e61b2752`** : "fix: re add mail template lost during merge" → +11 lignes restaurées sans commentaire. **Évitable** : grep `# pf:` voisin avant résolution.
- **`b53b91fdb2`** : 3 mois en prod avec mail confirmation OmniAuth cassé. **Évitable** : si FC touché, ouvrir checklist omniauth.
- **`78aefa3324`** : 100% mails de cron pointant vers `demarches.numerique.gouv.fr`. **Évitable** : audit sémantique des mailers (pas juste les tags PF).
- **PR #319** : PG::CheckViolation sur `attestation_templates.kind`. **Évitable** : croisement migration↔MT temporel.
- **PR #256 / `0e74d8afe4`** : cherry-pick "empty" silencieux. **Évitable** : `git diff origin/<branche-source>` après cherry-pick.

## Articulation avec les anciens agents

Les 5 agents `.claude/agents/upstream-*` ont été **archivés** (`.claude/agents.archived/`). Leur logique d'audit est consolidée dans ce skill, mais le paradigme a changé :

- **Avant** : agents = jugent une PR manuelle déjà créée
- **Maintenant** : skill = guide la création de la PR, vérifie en cours de route, STOP aux décisions

## Articulation avec `/md_release`

Les deux skills sont **complémentaires mais distincts** :

| Skill | Quand | Quoi |
|---|---|---|
| `upstream-integration` (ce skill) | Toutes les ~2 semaines | PR `feature/bump-AAAA-MM-JJ-NN` qui intègre 1 ou N releases upstream dans `devpf` |
| `/md_release` | Quand on consolide des PRs `feature/bump-*` mergées (et des dev locaux) en release PF | Release GitHub `pf-AAAA-MM-JJ` avec changelog agrégé (PF + intégrations upstream) |

Workflow type :
1. Plusieurs PRs `feature/bump-*` mergées dans `devpf` puis `masterpf`
2. Dév locaux mergés
3. `/md_release` agrège tout en une release PF datée

### ⚠️ Gap actuel à connaître sur `/md_release`

Le skill `/md_release` (`.claude/commands/md_release.md`) **ne mentionne pas les Maintenance Tasks à exécuter manuellement** (Issue B de `maintenance-task-decision.md`).

Quand tu utilises `/md_release` après avoir mergé des PRs `feature/bump-*` qui contiennent des MT en Issue B :

1. **Récupérer** la liste des MT Issue B des descriptions de PRs `feature/bump-*` agrégées
2. **Ajouter manuellement** une section dans la release PF :
   ```markdown
   ## ⚠️ Actions manuelles post-déploiement

   Lancer les Maintenance Tasks suivantes depuis l'interface admin :
   - `T20XXMMNN_xxx_task` — [raison]
   - `T20XXMMNN_yyy_task` — [raison]
   ```

Une amélioration de `/md_release` pour automatiser cette agrégation est planifiée (cf. task de suivi).

## Sous-fichiers du skill (chargement à la demande)

- [omniauth-franceconnect-checklist.md](./omniauth-franceconnect-checklist.md) — Si la PR touche FC, à ouvrir obligatoirement
- [conflict-resolution-patterns.md](./conflict-resolution-patterns.md) — Patterns par type de fichier
- [maintenance-task-decision.md](./maintenance-task-decision.md) — Arbre de décision pour chaque MT
- [post-merge-audit.md](./post-merge-audit.md) — Checks avant push
