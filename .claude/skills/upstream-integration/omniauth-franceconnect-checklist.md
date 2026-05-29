# OmniAuth ↔ FranceConnect — checklist de réplication

**À lire dès que la PR upstream touche un fichier `france_connect/`.**

## Pourquoi ce fichier existe (pépite)

Commit `b53b91fdb2` (2025-09-26) :

> *"Le bouton 'Confirmer mon compte par email' des connexions sociales (Google, Microsoft, Tatou, SIPF) affichait 'email envoyé' mais n'envoyait réellement aucun email. La fonctionnalité équivalente FranceConnect fonctionne correctement."*

→ **Durée du bug en prod : ~3 mois**. Cause : upstream `acc868d20d` "remove useless omniauth_merge_confirmation mailer" (côté FC) intégré sans répliquer côté OmniAuth.

C'est le pattern majeur identifié dans l'historique. Aucun tag `# pf:` ne pouvait protéger : c'est une question de **symétrie sémantique** entre deux mondes (FC stock upstream vs OmniAuth PF étendu).

## La règle

> **Si la PR touche `app/controllers/france_connect/`, `app/services/france_connect/`, `app/views/france_connect/` ou `config/locales/france_connect*` → audit obligatoire des fichiers OmniAuth équivalents.**

## Fichiers FC ↔ OmniAuth à croiser

| Fichier FC modifié upstream | Fichier OmniAuth PF à auditer |
|---|---|
| `app/controllers/france_connect/particulier_controller.rb` | `app/controllers/users/omniauth_callbacks_controller.rb`, `app/controllers/omniauth_controller.rb` |
| `app/services/france_connect/*` | `app/services/omniauth_*.rb`, `app/services/omniauth_merger_service.rb` |
| `app/views/france_connect/**` | `app/views/users/omniauth_*/**`, `app/views/users/devise/**` |
| `app/mailers/devise_*.rb` (touches FC) | Tout appel à `UserMailer.confirm_omniauth_*` |
| `config/locales/france_connect.fr.yml` | `config/locales/devise.fr.yml`, `config/locales/omniauth*.fr.yml` |
| `config/routes.rb` (zone `france_connect`) | Zone `omniauth_callbacks`, `users/omniauth_*` |
| Modèles `FranceConnectInformation`, `AgentConnectInformation` | `User#omniauth_*`, `User#confirmed_with_omniauth?` |

## Checklist d'audit (à exécuter manuellement)

Quand un fichier FC est en conflit ou modifié par upstream :

```bash
# 1. Examiner la modification upstream côté FC
git diff $DERNIER_TAG_PF..$TARGET_TAG -- app/controllers/france_connect/ app/services/france_connect/

# 2. Pour CHAQUE méthode FC modifiée/ajoutée/supprimée :
#    chercher l'équivalent OmniAuth
METHOD_NAME="..."  # ex: send_custom_confirmation_instructions
grep -rn "$METHOD_NAME" app/controllers/users/ app/services/omniauth*.rb \
                       app/services/*omniauth*.rb app/views/users/

# 3. Vérifier les clés i18n
# FC a souvent ses propres clés sous "france_connect.*"
# Si une clé est renommée/supprimée, vérifier qu'il n'y a pas d'usage côté omniauth
git diff $DERNIER_TAG_PF..$TARGET_TAG -- config/locales/france_connect*.yml
# → Pour chaque clé modifiée, chercher l'équivalent omniauth
grep -rn "I18n.t.*france_connect\." app/views/ app/controllers/

# 4. Vérifier les mailers
git diff $DERNIER_TAG_PF..$TARGET_TAG -- app/mailers/ app/views/*mailer*
# → Si une méthode mailer est supprimée upstream (FC),
#   vérifier qu'elle n'est PAS appelée depuis le flow omniauth PF

# 5. Vérifier les routes
git diff $DERNIER_TAG_PF..$TARGET_TAG -- config/routes.rb
# → Si une route FC change de nom, vérifier les helpers utilisés côté omniauth
grep -rn "_path\|_url" app/views/users/ | grep -iE "france_connect|merge|omniauth"
```

## Patterns historiques de divergence

### Pattern 1 : Méthode supprimée upstream, appelée côté OmniAuth

**Exemple** : `acc868d20d` supprime `UserMailer.omniauth_merge_confirmation` côté FC (upstream pensait qu'il était inutilisé). Côté OmniAuth PF, l'appel restait → bouton "envoyé" mais 0 mail.

**Check** : pour toute méthode mailer supprimée, `grep -rn "<methode>" app/controllers/ app/services/` doit être vide AVANT merge.

### Pattern 2 : Signature de méthode changée

**Exemple** : `985061b54d` "fix(omniauth): ajouter le paramètre provider manquant dans `merge_using_email_link`". Upstream a ajouté un paramètre côté FC, omniauth PF appelait l'ancienne signature.

**Check** : pour toute méthode de service utilisée par les deux flux, comparer la signature avant/après.

### Pattern 3 : Refactor naming (notation "particulier" supprimée)

**Exemple** : `4e08d36543` "adapter tests france_connect suite au refactoring upstream particulier" + `6a0dfb5eb6` "corriger chemins de routes FranceConnect". Upstream a supprimé la notation `particulier` dans les clés i18n (`france_connect.particulier.flash` → `france_connect.flash`).

**Check** : si la PR renomme/déplace des clés i18n FC, scan exhaustif des usages dans les vues, contrôleurs ET tests system.

### Pattern 4 : Nouveau provider/cookie upstream non géré côté Microsoft/Tatou

**Exemple** : `c248492e82` "Support hybride ProConnect (cookie) et Microsoft (loged_in_with_france_connect)". Upstream a introduit ProConnect via cookie sans considérer les providers PF.

**Check** : tout nouveau mécanisme de session/cookie côté FC → vérifier impact sur les providers OmniAuth PF (Tatou, Microsoft, SIPF, Google).

### Pattern 5 : Tests FC OK, tests OmniAuth OK séparément, mais workflow utilisateur cassé

**Exemple** : on relance `spec/controllers/france_connect/` ✅ + `spec/controllers/omniauth_controller_spec.rb` ✅ mais le **scénario réel** "utilisateur Tatou qui veut merger son compte avec un compte FC existant" casse.

**Check** : exécuter au moins un test système end-to-end qui couvre le merge OmniAuth↔FC (cf. `spec/system/users/` autour des providers).

## Tag `# pf:` à apposer systématiquement

Si tu adaptes du code suite à un audit FC↔OmniAuth, tagger :

```ruby
# pf: harmonisation avec France Connect pour maintenir la cohérence UX
def send_custom_confirmation_instructions(provider_type: :france_connect)
```

```ruby
# pf: méthode équivalente OmniAuth — upstream l'a supprimée côté FC,
# mais elle reste nécessaire pour Tatou/Microsoft/SIPF
def omniauth_merge_confirmation_mailer
```

## Quand DÉCIDER de ne pas répliquer

Cas où upstream supprime une fonctionnalité FC qu'on **veut garder** côté OmniAuth :

1. **Documenter explicitement** dans le commit : "pf: garder X côté omniauth bien qu'upstream l'ait supprimé côté FC parce que Y"
2. **Ajouter un tag `# pf:` à la méthode conservée** pour signaler aux futurs intégrateurs
3. **Mentionner dans la PR** sous "Adaptations PF"

## Quand DÉCIDER de répliquer

Cas où upstream améliore FC et on veut l'équivalent côté OmniAuth :

1. **Reproduire le changement côté OmniAuth** dans le même commit que le merge
2. **Tagger `# pf: harmonisation avec France Connect`**
3. **Ajouter un test équivalent côté OmniAuth** si upstream en a ajouté côté FC

## Rapport de l'audit (modèle)

À inclure dans la description de la PR :

```markdown
### Audit OmniAuth ↔ FranceConnect

Zones FC touchées par la release : [liste fichiers]

Réplication OmniAuth effectuée :
- [Méthode X] : répliquée dans omniauth_controller.rb
- [Clé i18n Y] : harmonisée dans devise.fr.yml
- ...

Réplication NON effectuée (avec justification) :
- [Comportement Z] : pas répliqué côté Tatou car [raison]

Tests joués :
- [ ] `spec/controllers/france_connect/`
- [ ] `spec/controllers/omniauth_controller_spec.rb`
- [ ] `spec/system/` scénario merge multi-provider
```
