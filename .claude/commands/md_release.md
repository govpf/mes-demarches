# Créer une release mes-demarches

Tu dois créer une release GitHub pour le projet mes-demarches en suivant EXACTEMENT la procédure documentée dans CLAUDE.md section "Processus de Release".

## Étapes à suivre

### 1. Vérifications préalables
- Vérifier que tu es sur la branche `masterpf`
- Identifier le dernier tag pf-AAAA-MM-JJ depuis `.git/refs/tags/`
- Analyser les commits depuis ce tag via `git log <dernier-tag>..masterpf --oneline`

### 2. Identification des releases upstream
- Chercher les commits de merge de tags upstream : `git log <dernier-tag>..masterpf --grep="Merge tag" --oneline`
- Pour chaque tag upstream identifié (format AAAA-MM-JJ-NN), récupérer le contenu EXACT de la release :
  ```bash
  gh release view AAAA-MM-JJ-NN --repo demarches-simplifiees/demarches-simplifiees.fr --json body --jq .body
  ```
- **CRITIQUE** : Ne PAS inclure d'éléments de releases postérieures à celle intégrée

### 3. Analyse des commits PF
- Identifier les commits spécifiques Polynésie (hors merge upstream)
- Classer par catégorie : Administrateur, Instructeur, Usager, Technique
- **Sémantiquement intéressant uniquement** : nouvelles fonctionnalités utilisateur, corrections importantes
- Détails techniques de maintenance → chapitre Technique

### 3 bis. Identification des Maintenance Tasks à exécuter manuellement

⚠️ **ÉTAPE CRITIQUE** — Sans cette étape, des MT critiques peuvent ne jamais être exécutées et causer des bugs silencieux en production (cf. cas historiques documentés dans `.claude/skills/upstream-integration/maintenance-task-decision.md`).

**Deux sources à croiser :**

#### Source A — Descriptions des PRs `feature/bump-*` agrégées

Le skill `upstream-integration` exige une section "Maintenance Tasks" avec mention explicite des MT Issue B (à lancer manuellement) dans chaque PR `feature/bump-*`.

```bash
DERNIER_TAG_PF=$(git tag -l "pf-*" | sort -V | tail -1)

# Lister les PRs feature/bump-* mergées depuis le dernier tag
PR_NUMBERS=$(git log $DERNIER_TAG_PF..masterpf --merges --oneline | \
  grep -oE "Feature/bump.*\(#[0-9]+\)" | grep -oE "#[0-9]+" | tr -d '#')

# Pour chaque PR, extraire les MT manuelles
for pr in $PR_NUMBERS; do
  echo "=== PR #$pr ==="
  gh pr view $pr --json body --jq .body | \
    grep -E "Manuel après déploiement|à lancer manuellement|run manually" -A 1
done
```

#### Source B — Scan de code (filet de sécurité)

Pour les PRs anciennes (avant l'adoption du skill `upstream-integration`) ou si une PR a oublié la section MT :

```bash
# Lister les nouvelles MT depuis le dernier tag PF
git diff $DERNIER_TAG_PF..masterpf --diff-filter=A --name-only -- app/tasks/maintenance/ | grep -v concerns/ | while read f; do
  # Détecter les MT de backfill / fix de données SANS run_on_first_deploy actif
  if grep -lE "update_all|update!|destroy|where.*nil" "$f" > /dev/null 2>&1; then
    if ! grep -qE "^    run_on_first_deploy$" "$f"; then
      echo "⚠️  $f — backfill/fix sans run_on_first_deploy actif"
      grep -m1 "class.*Task" "$f"
    fi
  fi
done
```

#### Décision

Pour chaque MT identifiée :
1. Vérifier dans le code si `run_on_first_deploy` est actif (décommenté) → si oui, **rien à signaler** (la MT tournera automatiquement au déploiement)
2. Si commenté ET la MT fait du backfill / fix de données → **À LISTER dans les actions manuelles**
3. Si commenté ET la MT est un nettoyage volumineux (`destroy_*_orphan_*`, `move_dol_*`) → **À LISTER** (avec mention de la lourdeur)

**Croisement** : si Source A ne mentionne pas une MT que Source B détecte → alerter l'utilisateur (la PR `feature/bump-*` a oublié la classification).

### 4. Structure du texte de release (FORMAT OBLIGATOIRE)

**IMPORTANT** : La section Polynésie doit être EN PREMIER, avant l'intégration upstream.

```markdown
## Améliorations et correctifs

### Polynésie

#### Administrateur
- [Description] (#commit-hash ou #PR)

#### Instructeur
- [Description] (#commit-hash ou #PR)

#### Usager
- [Description] (#commit-hash ou #PR)

#### Technique
- [Description] (#commit-hash ou #PR)

### Intégration de la release upstream AAAA-MM-JJ-NN

#### Administrateur
[COPIER EXACTEMENT le contenu de la release upstream]

#### Instructeur
[COPIER EXACTEMENT le contenu de la release upstream]

#### Usager
[COPIER EXACTEMENT le contenu de la release upstream]

#### API
[COPIER EXACTEMENT le contenu de la release upstream]

#### Technique
[COPIER EXACTEMENT le contenu de la release upstream]
```

### 5. Migrations (si applicable)
Si des migrations ont été ajoutées, ajouter une section :
```markdown
## Migrations

- NomDeLaMigration : description
```

### 5 bis. Actions manuelles post-déploiement (si applicable)

Si l'étape 3 bis a identifié des Maintenance Tasks à exécuter manuellement, ajouter une section **AVANT** les Migrations :

```markdown
## ⚠️ Actions manuelles post-déploiement

Après le déploiement, lancer manuellement les Maintenance Tasks suivantes depuis l'interface
d'administration (`/admin/maintenance_tasks`) :

- [ ] `Maintenance::T20XXMMNN_NomTask` — [Raison : ce que ça fait, pourquoi c'est important, ordre d'exécution si dépendances]
- [ ] `Maintenance::T20XXMMNN_AutreTask` — [...]

**Ne PAS oublier** : ces tâches sont commentées `# run_on_first_deploy` et ne s'exécutent donc PAS automatiquement au déploiement.
```

**Ordre dans la release** :
1. `## Améliorations et correctifs` (Polynésie + Intégration upstream)
2. `## ⚠️ Actions manuelles post-déploiement` (si MT Issue B)
3. `## Migrations` (si migrations ajoutées)

### 6. Création de la release GitHub

**IMPORTANT** : Ne PAS créer de tag local avant. Laisser GitHub créer le tag automatiquement.

```bash
gh release create pf-AAAA-MM-JJ --title "JJ mois AAAA" --notes "$(cat <<'EOF'
[CONTENU COMPLET DE LA RELEASE ICI]
EOF
)"
```

**Format du titre** : Date du jour en FRANÇAIS format LONG
- Exemples corrects : "05 novembre 2025", "23 décembre 2024", "01 janvier 2026"
- Format incorrect : "05 Nov 2025" (anglais)

### 7. Vérification
- Vérifier sur GitHub : https://github.com/govpf/mes-demarches/releases
- Vérifier que le tag a été créé automatiquement dans `.git/refs/tags/`

## Erreurs critiques à éviter

- **NE JAMAIS** mélanger des éléments de plusieurs releases upstream
- **NE JAMAIS** inventer ou modifier les numéros d'issues upstream
- **NE JAMAIS** omettre l'étape 3 bis (identification des MT manuelles) — risque de bugs silencieux en prod si une MT critique n'est pas exécutée
- **TOUJOURS** respecter le chapitrage exact : Administrateur, Instructeur, Usager, API, Technique
- **TOUJOURS** utiliser le format "ETQ" (En Tant Que) des releases upstream tel quel
- **TOUJOURS** mettre la section Polynésie EN PREMIER
- **TOUJOURS** utiliser la date en FRANÇAIS dans le titre (ex: "05 novembre 2025")
- **VÉRIFIER** que la release upstream identifiée correspond bien aux commits intégrés
- **CROISER** Source A (descriptions PRs `feature/bump-*`) et Source B (scan code MT) lors de l'étape 3 bis

## Notes importantes

- Utiliser la date du jour pour le tag pf-AAAA-MM-JJ
- Les numéros d'issues upstream (#NNNNN) doivent être copiés exactement
- Les commits PF peuvent référencer soit un hash court (#7bb5c71) soit un numéro de PR (#228)
- Le titre doit impérativement être en français : "05 novembre 2025" et non "05 Nov 2025"
