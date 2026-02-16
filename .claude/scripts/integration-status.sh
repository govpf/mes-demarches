#!/bin/bash

# Script de monitoring de l'état des intégrations upstream
# Usage: ./scripts/integration-status.sh

set -e

echo "🚀 État des Intégrations Upstream - $(date)"
echo "=============================================="

# État des remotes
echo ""
echo "📡 Configuration remotes:"
git remote -v | grep -E "(origin|upstream)"

# État actuel
echo ""
echo "📊 État actuel:"
LAST_PF=$(git tag -l "pf-*" | sort -V | tail -1)
LAST_UPSTREAM=$(git tag -l "2024-*" "2025-*" | sort -V | tail -1)
PENDING_COUNT=$(git tag -l "2024-*" "2025-*" | wc -l)

echo "  Dernière release PF: $LAST_PF"
echo "  Dernière release upstream: $LAST_UPSTREAM"
echo "  Releases en attente: $PENDING_COUNT"

# Analyse de l'écart
if [ -n "$LAST_PF" ] && [ -n "$LAST_UPSTREAM" ]; then
    echo ""
    echo "🎯 Analyse de l'écart:"
    
    # Extraire les dates pour calculer l'écart
    PF_DATE=$(echo $LAST_PF | sed 's/pf-//')
    UPSTREAM_DATE=$(echo $LAST_UPSTREAM | cut -d'-' -f1-3)
    
    echo "  Date release PF: $PF_DATE"
    echo "  Date release upstream: $UPSTREAM_DATE"
    
    # Calculer l'écart approximatif
    if [[ "$PF_DATE" < "$UPSTREAM_DATE" ]]; then
        echo "  ⚠️  Retard détecté"
    else
        echo "  ✅ À jour"
    fi
fi

# État des PRs
echo ""
echo "📋 PRs en cours:"
if command -v gh &> /dev/null; then
    gh pr list --state open --limit 5 || echo "  Aucune PR ou erreur GitHub CLI"
else
    echo "  GitHub CLI non disponible"
fi

# Branches d'intégration actives
echo ""
echo "🌿 Branches d'intégration:"
git branch | grep -E "(feature/bump|test/integration)" | head -5 || echo "  Aucune branche d'intégration active"

# Tests PF rapides
echo ""
echo "🧪 État des tests PF (rapide):"
if [ -f "Gemfile" ]; then
    echo "  Lancement tests critiques..."
    bundle exec rspec spec/models/champs/ -e "DN|Commune" --format dots --quiet 2>/dev/null && echo "  ✅ Tests champs PF: OK" || echo "  ❌ Tests champs PF: ÉCHEC"
    bundle exec rspec spec/controllers/omniauth_controller_spec.rb --format dots --quiet 2>/dev/null && echo "  ✅ Tests auth PF: OK" || echo "  ❌ Tests auth PF: ÉCHEC"
else
    echo "  Pas de Gemfile détecté"
fi

# Prochaines actions recommandées
echo ""
echo "📝 Prochaines actions recommandées:"

# Trouver la prochaine release à intégrer
LAST_INTEGRATED=$(git log --oneline --grep="upstream\|bump" -1 --format="%s" | grep -oE "20[0-9]{2}-[0-9]{2}-[0-9]{2}(-[0-9]+)?" | head -1)
if [ -n "$LAST_INTEGRATED" ]; then
    NEXT_RELEASES=$(git tag -l "2024-*" "2025-*" | sort -V | grep -A3 "$LAST_INTEGRATED" | tail -3)
    echo "  Dernière intégrée: $LAST_INTEGRATED"
    echo "  Prochaines à intégrer:"
    echo "$NEXT_RELEASES" | head -3 | sed 's/^/    - /'
else
    echo "  Analyser l'historique pour identifier la prochaine release"
fi

echo ""
echo "🎯 Pour démarrer une intégration:"
echo "  claude --agent upstream-analyzer \"Analyse l'impact de la release [TAG]\""
echo ""
echo "📚 Documentation: .claude/agents/README.md"