# Audit post-merge — checks avant le push de la PR

**À exécuter après la résolution de tous les conflits, AVANT `git push` et `gh pr create`.**

## Principe

Les fix post-merge représentent en moyenne **21 commits par PR** sur les 15 dernières intégrations. La plupart auraient été détectables par des checks systématiques avant push. Ce fichier est cette systématique.

## Ordre d'exécution

1. Cohérence d'environnement (versions, deps)
2. Schéma GraphQL régénéré
3. Tests PF critiques
4. Audit code PF (tags, régressions silencieuses)
5. Audit migrations / MT
6. Audit OmniAuth/FC si applicable
7. Audit cascade formule si applicable
8. Diff final visuel

## 1. Cohérence d'environnement

```bash
# Ruby
RUBY_FILE=$(cat .ruby-version)
DOCKERFILE_RUBY=$(grep "FROM ruby:" Dockerfile | grep -oP '\d+\.\d+\.\d+' | head -1)
if [ "$RUBY_FILE" != "$DOCKERFILE_RUBY" ]; then
  echo "🔴 INCOHÉRENCE Ruby : .ruby-version=$RUBY_FILE vs Dockerfile=$DOCKERFILE_RUBY"
fi

# Gemfile / Gemfile.lock
bundle check || (echo "🔴 Gemfile.lock désynchronisé" && bundle install)

# Node / bun
bun install --frozen-lockfile 2>&1 | tail -5

# Verifier qu'aucun gem PF n'a disparu
git diff $DERNIER_TAG_PF..HEAD -- Gemfile | grep "^-gem" | grep -iE "siret_validator|tatou|polynesie|baserow"
# Si match → gem PF supprimée par accident
```

## 2. Schéma GraphQL

```bash
bin/rails graphql:schema:dump
git status -- schema.graphql

# Si schema.graphql a bougé → vérifier
git diff schema.graphql | head -100

# Vérifier qu'aucun type PF n'a disparu
for type in ReferentielDePolynesie Visa TeFenua DossierPolynesie; do
  count=$(grep -c "type $type" schema.graphql 2>/dev/null || echo 0)
  [ "$count" -eq 0 ] && echo "⚠️ Type $type ABSENT du schema"
done
```

## 3. Tests PF critiques

```bash
# Suite minimale
bundle exec rspec \
  spec/models/champs/ \
  spec/controllers/omniauth_controller_spec.rb \
  spec/controllers/api/v2/graphql_controller_spec.rb \
  spec/models/champs/formule_cascade_audit_spec.rb \
  spec/models/concerns/dossier_clone_concern_spec.rb \
  spec/services/formula_calculation_service_spec.rb 2>&1 | tail -20
```

🛑 STOP si un seul test PF échoue. Pas de push tant que la suite minimale n'est pas verte.

## 4. Audit code PF

### 4a. Tags `# pf:` perdus

```bash
# Compter les tags avant et après merge
BEFORE=$(git show $DERNIER_TAG_PF:./ 2>/dev/null | grep -rc "# pf:" 2>/dev/null)
AFTER=$(grep -rc "# pf:" app/ config/ db/ lib/ spec/ 2>/dev/null | awk -F: '{sum+=$2} END {print sum}')
echo "Tags # pf: : avant=$BEFORE, après=$AFTER"

# Si AFTER < BEFORE - 5 (tolérance pour fichiers vraiment supprimés) → investiguer
git diff $DERNIER_TAG_PF..HEAD | grep "^-.*# pf:" | head -30
# → pour chaque ligne supprimée, vérifier si c'est légitime
```

### 4b. Fichiers critiques modifiés sans tag `# pf:` ajouté

Si la PR modifie un de ces fichiers, **un tag `# pf:` aurait dû être ajouté à l'endroit modifié** :

```bash
HIGH_RISK_FILES=(
  "app/models/champs/referentiel_de_polynesie_champ.rb"
  "app/models/champs/visa_champ.rb"
  "app/models/champs/te_fenua_champ.rb"
  "app/controllers/omniauth_controller.rb"
  "app/services/omniauth_merger_service.rb"
  "app/services/api/baserow_service.rb"
  "app/services/tiptap_service.rb"
)

for f in "${HIGH_RISK_FILES[@]}"; do
  if git diff $DERNIER_TAG_PF..HEAD --name-only | grep -q "^$f$"; then
    NEW_PF=$(git diff $DERNIER_TAG_PF..HEAD -- "$f" | grep -c "^+.*# pf:")
    echo "$f : modifié, +$NEW_PF tag(s) # pf: ajouté(s)"
  fi
done
```

### 4c. Régression silencieuse (code PF non taggé écrasé)

Particulièrement pour les fichiers suivants (cas historiques de régression sans tag) :

```bash
RISKY_NOTAG=(
  "app/services/tiptap_service.rb"           # cas 4384704e24
  "app/models/procedure.rb"                  # cas f3e61b2752
  "app/models/champs/decimal_number_champ.rb" # cas 11363e8e16
)

for f in "${RISKY_NOTAG[@]}"; do
  if git diff $DERNIER_TAG_PF..HEAD --name-only | grep -q "^$f$"; then
    echo "=== $f ==="
    echo "Lignes supprimées :"
    git diff $DERNIER_TAG_PF..HEAD -- "$f" | grep "^-" | grep -v "^---" | head -20
    echo ""
    echo "🛑 Vérifier manuellement qu'aucune logique PF n'a été perdue"
  fi
done
```

🛑 STOP utilisateur si une suppression suspecte est détectée.

## 5. Audit migrations / MT

```bash
# Migrations qui posent des contraintes
git diff $DERNIER_TAG_PF..HEAD --diff-filter=A --name-only -- db/migrate/ | while read f; do
  if grep -lE "change_column_null|validate_check_constraint|add_check_constraint.*validate: true" "$f" > /dev/null; then
    echo "🟡 Contrainte ajoutée : $f"
  fi
done

# MT sans run_on_first_deploy alors qu'elles font du backfill
git diff $DERNIER_TAG_PF..HEAD --diff-filter=A --name-only -- app/tasks/maintenance/ | grep -v concerns/ | while read f; do
  if grep -lE "update_all|where.*nil" "$f" > /dev/null && ! grep -q "^    run_on_first_deploy$" "$f"; then
    echo "⚠️ MT de backfill SANS run_on_first_deploy actif : $f"
    echo "   → Vérifier via maintenance-task-decision.md"
  fi
done

# Lancer la migration pour vérifier qu'elle passe
RAILS_ENV=test bin/rails db:drop db:create db:schema:load db:migrate 2>&1 | tail -20
# Si PG::CheckViolation → STOP, problème multi-release
```

## 6. Audit OmniAuth/FC

Si la PR touche `france_connect/` :

```bash
# Liste des fichiers FC modifiés
FC_TOUCHED=$(git diff $DERNIER_TAG_PF..HEAD --name-only | grep -E "france_connect|agent_connect")
echo "Fichiers FC touchés : $FC_TOUCHED"

# Vérifier que omniauth a aussi été audité (au minimum lu)
OMNIAUTH_TOUCHED=$(git diff $DERNIER_TAG_PF..HEAD --name-only | grep -E "omniauth")
if [ -n "$FC_TOUCHED" ] && [ -z "$OMNIAUTH_TOUCHED" ]; then
  echo "🛑 FC touché mais AUCUN fichier omniauth modifié — audit manuel obligatoire"
  echo "   → Suivre omniauth-franceconnect-checklist.md"
fi
```

## 7. Audit cascade formule

Si la PR touche un concern de dossier :

```bash
DOSSIER_CONCERNS_TOUCHED=$(git diff $DERNIER_TAG_PF..HEAD --name-only | grep -E "dossier_(champs|rebase|clone|prefillable)_concern\.rb")
if [ -n "$DOSSIER_CONCERNS_TOUCHED" ]; then
  echo "⚠️ Concern dossier touché : $DOSSIER_CONCERNS_TOUCHED"
  echo "→ Audit cascade formule obligatoire"

  # Tests dédiés
  bundle exec rspec spec/models/champs/formule_cascade_audit_spec.rb \
                    spec/models/concerns/dossier_clone_concern_spec.rb
fi
```

CLAUDE.md section "Cascade des formules" liste les sites qui doivent appeler `dossier.refresh_formulas_after(champ)`. Vérifier qu'aucun nouveau sentier n'a été créé par upstream sans cet appel.

## 8. Diff final visuel

```bash
# Stats globales
git diff $DERNIER_TAG_PF..HEAD --stat | tail -5

# Fichiers modifiés sans tag # pf: ajouté (suspect si fichier sensible)
git diff $DERNIER_TAG_PF..HEAD --name-only > /tmp/changed.txt
wc -l /tmp/changed.txt

# Verifier qu'aucun fichier hors scope n'a été touché
# (ex: README.md, CLAUDE.md, .github/ — typique d'un --add . accidentel)
git diff $DERNIER_TAG_PF..HEAD --name-only | grep -E "^(README|CLAUDE|french_polynesia|TODO)\.md$|^\.github/"
```

## Checklist finale (à inclure dans la PR)

```markdown
### Checks post-merge

#### Cohérence d'environnement
- [ ] `.ruby-version` cohérent avec `Dockerfile`
- [ ] `bundle check` OK
- [ ] `bun install --frozen-lockfile` OK
- [ ] Aucune gem PF supprimée par accident

#### Schéma et types
- [ ] `bin/rails graphql:schema:dump` exécuté
- [ ] Tous les types PF présents dans `schema.graphql`

#### Tests
- [ ] Suite PF critique verte
- [ ] `spec/models/champs/` ✅
- [ ] `spec/controllers/omniauth_controller_spec.rb` ✅
- [ ] `spec/controllers/api/v2/graphql_controller_spec.rb` ✅
- [ ] `spec/services/formula_calculation_service_spec.rb` ✅ (si concerns touchés)

#### Code PF
- [ ] Aucun tag `# pf:` supprimé sans justification
- [ ] Fichiers critiques modifiés : tags `# pf:` ajoutés là où c'est nécessaire
- [ ] Fichiers risky-notag (tiptap, procedure, decimal_number_champ) vérifiés manuellement

#### Migrations / MT
- [ ] `db:migrate` passe sans `PG::CheckViolation`
- [ ] Chaque nouvelle MT a une décision documentée (auto/manuel/intégré)
- [ ] Cas multi-release : pas de MT intercalée non gérée

#### OmniAuth/FC (si applicable)
- [ ] Si FC touché → audit omniauth fait et documenté
- [ ] Tests merge multi-provider passés

#### Cascade formule (si concerns dossier touchés)
- [ ] `spec/models/champs/formule_cascade_audit_spec.rb` ✅
- [ ] `spec/models/concerns/dossier_clone_concern_spec.rb` ✅
- [ ] Nouveaux sentiers de modification de champ → `refresh_formulas_after` ajouté
```

🛑 STOP utilisateur après ce rapport. Ne pas push sans validation explicite.
