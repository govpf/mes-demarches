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
- **TOUJOURS** respecter le chapitrage exact : Administrateur, Instructeur, Usager, API, Technique
- **TOUJOURS** utiliser le format "ETQ" (En Tant Que) des releases upstream tel quel
- **TOUJOURS** mettre la section Polynésie EN PREMIER
- **TOUJOURS** utiliser la date en FRANÇAIS dans le titre (ex: "05 novembre 2025")
- **VÉRIFIER** que la release upstream identifiée correspond bien aux commits intégrés

## Notes importantes

- Utiliser la date du jour pour le tag pf-AAAA-MM-JJ
- Les numéros d'issues upstream (#NNNNN) doivent être copiés exactement
- Les commits PF peuvent référencer soit un hash court (#7bb5c71) soit un numéro de PR (#228)
- Le titre doit impérativement être en français : "05 novembre 2025" et non "05 Nov 2025"
