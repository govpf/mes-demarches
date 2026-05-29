# Maintenance Task — arbre de décision auto-startup vs manuel

**À ouvrir pour CHAQUE nouvelle Maintenance Task ajoutée par une release upstream.**

## Pourquoi ce fichier existe

Le template `lib/templates/maintenance_tasks/task.rb.tt` génère par défaut :

```ruby
# Uncomment only if this task MUST run imperatively on its first deployment.
# If possible, leave commented for manual execution later.
# run_on_first_deploy
```

**Le défaut est : commenté.** En pratique, la majorité des MT upstream **devraient** tourner au déploiement (backfill, fix de données, nettoyage), mais l'info se perd entre le moment où upstream prévoit l'exécution manuelle et le moment où on déploie en PF. Résultat : MT pas jouée → bug silencieux, ou pire, contrainte de base de données qui échoue plus tard.

## Mécanisme PF custom

Le concern `Maintenance::RunnableOnDeployConcern` (`app/tasks/maintenance/concerns/runnable_on_deploy_concern.rb`) :

```ruby
def run_on_first_deploy
  @run_on_first_deploy = true
end

def run_on_deploy?
  return false unless @run_on_first_deploy
  task = MaintenanceTasks::TaskDataShow.new(name)
  return false if task.completed_runs.not_errored.any?
  return false if task.active_runs.any?
  true
end
```

Activé via `run_on_first_deploy` (appel de méthode dans la classe). Une fois la MT exécutée avec succès, elle ne se relance pas.

## Arbre de décision (à appliquer pour CHAQUE nouvelle MT)

```
La MT modifie-t-elle des données existantes ?
│
├── NON (juste une lecture / un calcul / un log)
│   └── ➜ ISSUE B : laisser commenté, pas critique
│
└── OUI (update_all, update!, destroy, create...)
    │
    ├── La MT est-elle un BACKFILL de colonne ?
    │   │
    │   ├── OUI
    │   │   │
    │   │   ├── Une migration ultérieure pose-t-elle une contrainte (NOT NULL, CHECK, UNIQUE)
    │   │   │   sur cette même colonne ?
    │   │   │   │
    │   │   │   ├── OUI ➜ ISSUE C : intégrer le backfill DANS la migration
    │   │   │   │         (cf. conflict-resolution-patterns.md catégorie 3)
    │   │   │   │
    │   │   │   └── NON ➜ ISSUE A : décommenter run_on_first_deploy
    │   │   │
    │   │   └── (toujours ISSUE A si pas de contrainte qui suit)
    │   │
    │   └── NON
    │       │
    │       ├── La MT est-elle un FIX de données corrompues / orphelines / invalides ?
    │       │   ➜ ISSUE A : décommenter run_on_first_deploy
    │       │
    │       ├── La MT est-elle un NETTOYAGE (destroy_*, clean_*) ?
    │       │   │
    │       │   ├── Volume estimé < 100k records ➜ ISSUE A
    │       │   └── Volume estimé > 100k records ➜ ISSUE B + mention release notes
    │       │
    │       └── La MT est-elle une MIGRATION DE DONNÉES VOLUMINEUSE ?
    │           ➜ ISSUE B : laisser commenté + mention CRITIQUE dans release notes
```

## Les trois issues détaillées

### Issue A — Décommenter `run_on_first_deploy`

**Quand** : backfill, fix, nettoyage de petit volume.

**Action** :

```ruby
module Maintenance
  class T20XXMMNNBackfillSomethingTask < MaintenanceTasks::Task
    include RunnableOnDeployConcern

    run_on_first_deploy   # ← décommenter

    # ...
  end
end
```

**À documenter** dans la PR (section "Maintenance Tasks") :

```markdown
- ✅ Auto : `T20XXMMNNBackfillSomethingTask` (décommentage `run_on_first_deploy`)
  Raison : backfill nécessaire avant contrainte de la migration 20XXMMNN.
```

### Issue B — Laisser commenté + mention release notes

**Quand** : migration volumineuse, action non urgente, ou action manuelle déjà prévue par upstream.

**Action** :

1. **Laisser `# run_on_first_deploy` commenté**
2. **Ajouter à la section release notes du `pf-AAAA-MM-JJ.md`** (création de release) :

```markdown
## ⚠️ Actions manuelles post-déploiement

Après le déploiement, lancer manuellement la(les) MT suivante(s) depuis l'interface
maintenance_tasks :

- [ ] `T20XXMMNN_my_task_name` — [Raison : ce que ça fait, pourquoi c'est important]
```

3. **Documenter dans la PR `feature/bump-*`** :

```markdown
- ⚠️ **Manuel après déploiement** : `T20XXMMNNXxx` — raison : [...]
```

### Issue C — Intégrer le backfill dans la migration

**Quand** : pattern multi-releases avec MT intercalée + contrainte qui suit (cas PR #319).

**Action** : modifier la migration qui pose la contrainte :

```ruby
class ValidateAddDefaultFalseToAttestationTemplatesKind < ActiveRecord::Migration[7.0]
  def up
    # pf: backfill avant contrainte — upstream utilise une MT intercalée entre 2 releases
    safety_assured do
      execute("UPDATE attestation_templates SET kind = 'acceptation' WHERE kind IS NULL")
    end
    validate_check_constraint :attestation_templates, name: "attestation_templates_kind_null"
  end

  def down
    # ...
  end
end
```

Et **laisser la MT commentée** (elle ne sert plus, ou la supprimer si vraiment redondante).

## Catégorisation rapide par nom de tâche

| Préfixe nom | Catégorie probable | Issue par défaut |
|---|---|---|
| `backfill_*`, `*BackfillTask` | Backfill | A (sauf si contrainte qui suit → C) |
| `fix_*`, `*FixTask` | Fix de données | A |
| `destroy_*_orphan*`, `destroy_*_invalid*` | Nettoyage | A si petit volume, sinon B |
| `clean_*`, `*CleanTask` | Nettoyage | A si petit volume, sinon B |
| `normalize_*` | Normalisation | A |
| `populate_*` | Backfill | A |
| `copy_*`, `move_*` | Migration de données | B + check perf |
| `create_previews_*`, `create_variants_*` | Génération assets | B (lourd, manuel) |
| `move_dol_to_cold_storage` | Archivage | B (très lourd) |

## Check obligatoire AVANT de décider

```bash
# Lister les nouvelles MT
NEW_TASKS=$(git diff $DERNIER_TAG_PF..$TARGET_TAG --diff-filter=A --name-only -- app/tasks/maintenance/ | grep -v concerns/)

for task in $NEW_TASKS; do
  echo "=== $task ==="
  echo "--- État run_on_first_deploy ---"
  grep -n "run_on_first_deploy" "$task" || echo "  (absent)"
  echo "--- Type d'opération ---"
  grep -nE "update_all|update!|destroy|create|where.*nil" "$task" | head -5
  echo "--- Documentation upstream (release notes) ---"
  # À croiser avec : gh release view AAAA-MM-JJ-NN --repo demarches-simplifiees/demarches-simplifiees.fr
  echo ""
done
```

## Croisement avec les release notes upstream

**À faire systématiquement** : récupérer le contenu de la release upstream et chercher les mentions de la MT.

```bash
gh release view <TARGET_TAG> --repo demarches-simplifiees/demarches-simplifiees.fr | grep -iE "maintenance|task|backfill|à exécuter|à lancer"
```

Indices :
- "à exécuter après déploiement" / "à lancer manuellement" → Issue B
- "automatique" / "se lance au déploiement" / "backfill" sans mention de manuel → Issue A
- Aucune mention → décider via l'arbre

## Pattern multi-releases (réminder critique)

Si la PR cumule N releases upstream, le risque PG::CheckViolation est élevé. **Procédure** :

1. Lister TOUTES les migrations entre `$DERNIER_TAG_PF` et la dernière release du cumul
2. Lister TOUTES les nouvelles MT entre les mêmes points
3. Pour chaque MT de backfill : repérer la table.colonne concernée
4. Pour chaque migration de contrainte (NOT NULL, CHECK, UNIQUE) : repérer la table.colonne concernée
5. **Croiser temporellement** : si une MT backfill une colonne ET une migration ultérieure pose une contrainte dessus → Issue C **obligatoire**

🛑 STOP utilisateur si le pattern multi-release est détecté avec contrainte intercalée — il peut décider de splitter la PR en 2.

## Rapport final (à inclure dans la PR)

```markdown
### Maintenance Tasks

| Tâche | run_on_first_deploy | Décision | Raison |
|---|---|---|---|
| `T20XXMMNN_backfill_xxx_task` | ✅ Décommenté | Issue A | Backfill de petite taille, pas de contrainte qui suit |
| `T20XXMMNN_destroy_orphan_yyy_task` | ✅ Décommenté | Issue A | Nettoyage orphelins |
| `T20XXMMNN_normalize_zzz_task` | ❌ Commenté | Issue B | Mentionné dans release notes (volumineux, à lancer hors heures de pointe) |
| `T20XXMMNN_backfill_kkk_task` | N/A | Issue C | Backfill intégré dans migration 20XXMMNN_validate_check_kkk |
```
