# Équipe d'Agents Claude - Intégration Upstream

## Vue d'ensemble

Cette équipe d'agents Claude spécialisés est conçue pour rattraper les 9 mois de retard d'intégration upstream de `demarches-simplifiees.fr` vers `mes-demarches` (Polynésie française).

### Objectifs
- **Rattrapage** : 9 mois → 1 mois de retard d'ici 6-9 mois
- **Qualité** : 0 régression critique sur les fonctionnalités PF
- **Coordination** : Intégrer les développements locaux parallèles

## Agents disponibles

### 🔍 **Upstream-Analyzer**
**Rôle** : Analyse d'impact des releases upstream sur les spécificités PF
- Analyse différentielle entre releases consécutives
- Détection des conflits avec tags `# pf:`
- Classification CRITIQUE/MAJEUR/MINEUR
- Recommandations d'intégration

**Usage** :
```bash
claude --agent upstream-analyzer "Analyse l'impact de la release 2024-12-17-01"
```

### ⚙️ **Upstream-Integrator**
**Rôle** : Exécution technique des merges avec préservation PF
- Stratégie d'intégration minimale
- Préservation systématique des tags `# pf:`
- Résolution de conflits intelligente
- Adaptation des spécificités PF

**Usage** :
```bash
claude --agent upstream-integrator "Intègre la release 2024-12-17-01 selon le plan d'analyse"
```

### 🧪 **PF-Validator**
**Rôle** : Validation des fonctionnalités PF post-intégration
- Tests automatiques ciblés (auth, champs, attestations)
- Tests manuels critiques
- Détection de régressions
- Validation finale pour déploiement

**Usage** :
```bash
claude --agent pf-validator "Valide l'intégration de la release 2024-12-17-01"
```

### 📋 **Integration-Coordinator**
**Rôle** : Chef d'orchestre et planificateur stratégique
- Planification des intégrations
- Coordination entre agents
- Gestion des développements parallèles
- Interface avec l'équipe humaine

**Usage** :
```bash
claude --agent integration-coordinator "Planifie les intégrations de la semaine"
```

### 🤝 **Human-Collaborator**
**Rôle** : Interface avec le développeur humain
- Analyse des PRs préparées
- Coordination des contributions humaines
- Résolution de conflits d'approche
- Optimisation de la collaboration humain-IA

**Usage** :
```bash
claude --agent human-collaborator "Analyse les conflits entre PRs humaines et release 2024-12-17-01"
```

## Workflow d'intégration type

### 1. **Planification** (Integration-Coordinator)
```bash
claude --agent integration-coordinator "État des intégrations et planification semaine"
```

### 2. **Analyse d'impact** (Upstream-Analyzer)
```bash
claude --agent upstream-analyzer "Analyse l'impact de la release [TAG]"
```

### 3. **Coordination humaine** (Human-Collaborator) [si nécessaire]
```bash
claude --agent human-collaborator "Coordonne PRs humaines avec release [TAG]"
```

### 4. **Intégration** (Upstream-Integrator)
```bash
claude --agent upstream-integrator "Intègre la release [TAG]"
```

### 5. **Validation** (PF-Validator)
```bash
claude --agent pf-validator "Valide l'intégration de [TAG]"
```

### 6. **Décision finale** (Integration-Coordinator)
```bash
claude --agent integration-coordinator "Décide du déploiement basé sur validation"
```

## Démarrage rapide

### Setup initial
```bash
# Vérifier la configuration
git remote -v  # upstream doit pointer vers demarches-simplifiees
git fetch upstream --tags

# Identifier l'état actuel
git tag -l "pf-*" | sort -V | tail -1  # Dernière release PF
git tag -l "2024-*" "2025-*" | sort -V | tail -5  # Releases upstream récentes
```

### Premier test (release simple)
```bash
# 1. Analyser une release mineure
claude --agent upstream-analyzer "Analyse l'impact de la release 2024-12-17-02"

# 2. Si impact MINEUR → intégrer
claude --agent upstream-integrator "Intègre 2024-12-17-02"

# 3. Valider
claude --agent pf-validator "Valide l'intégration de 2024-12-17-02"
```

## Bonnes pratiques

### ✅ **À faire**
- **Toujours** lire CLAUDE.md avant utilisation des agents
- **Toujours** analyser avant d'intégrer
- **Toujours** intégrer les releases dans l'ordre chronologique
- **Toujours** valider après intégration
- **Documenter** toutes les adaptations avec `# pf:`

### ❌ **À éviter**
- Intégrer sans analyse préalable
- Sauter des releases (risque de confusion)
- Modifier le code PF sans tags `# pf:`
- Ignorer les rapports de validation
- Déployer avec des tests critiques en échec

## Métriques de suivi

### Dashboard recommandé
```bash
# État actuel
echo "Dernière release PF: $(git tag -l 'pf-*' | sort -V | tail -1)"
echo "Dernière release upstream: $(git tag -l '2024-*' '2025-*' | sort -V | tail -1)"
echo "Releases en attente: $(git tag -l '2024-*' '2025-*' | wc -l)"

# Tests PF
bundle exec rspec spec/models/champs/ -e "DN|Commune|Visa" --format progress
```

### Objectifs de vélocité
- **Semaine 1-2** : 1-2 releases/semaine (apprentissage)
- **Mois 2-3** : 3-5 releases/semaine (rythme de croisière)
- **Mois 4-6** : 5-8 releases/semaine (rattrapage intensif)

## Escalations

### Problèmes techniques
- **Agent bloqué** → Redirection vers agent approprié
- **Conflit complexe** → Implication développeur humain
- **Régression critique** → Rollback immédiat

### Arbitrages métier
- **Deadline vs qualité** → Chef de projet
- **Priorisation** → Product owner
- **Architecture** → Lead technique

## Support et maintenance

### Mise à jour des agents
- Adapter les configurations selon l'évolution du projet
- Enrichir les patterns d'adaptation PF
- Optimiser les workflows selon l'expérience

### Documentation
- Maintenir CLAUDE.md à jour
- Documenter les nouveaux patterns PF
- Archiver les décisions d'architecture importantes