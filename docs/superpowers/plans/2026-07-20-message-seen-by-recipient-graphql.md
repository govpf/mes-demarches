# Exposition GraphQL `seenByRecipientAt` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exposer l'instant de lecture d'un message (`Commentaire#seen_by_recipient_at`) dans l'API GraphQL, sur le type `Message`, pour qu'un process externe puisse déclencher un délai à partir de la lecture par l'usager.

**Architecture:** Ajout d'un unique champ nullable `seenByRecipientAt` (résolveur par défaut, mapping direct sur la colonne indexée) au type GraphQL existant `Types::MessageType`. Aucune logique métier, aucune migration, aucun changement au marquage « lu » existant. Régénération du schéma figé + test GraphQL de non-régression.

**Tech Stack:** Ruby 3.3.2, Rails 7.0, graphql-ruby, RSpec.

## Global Constraints

- **Tag PF obligatoire** : le champ est une addition PF sur du code upstream → commentaire `# pf:` au-dessus de la déclaration, à préserver aux merges `feature/bump-*`.
- **Nom GraphQL** : `seenByRecipientAt` (camelCase auto depuis `seen_by_recipient_at`). Type `GraphQL::Types::ISO8601DateTime`, `null: true`.
- **Schéma figé** : toute modif de type GraphQL DOIT être suivie de `bin/rails graphql:schema:dump` ; le diff sur `app/graphql/schema.graphql` fait partie du commit.
- **Aucune modification** des méthodes `Commentaire.mark_*_as_seen` ni de `update_all` (hors périmètre, cf. spec).
- **Quotes françaises** dans tout texte d'interface (sans objet ici : la `description` du champ est de la doc API, pas de l'UI — texte simple accepté).
- Branche de travail : `feature/message-seen-by-recipient-graphql` (déjà créée, contient la spec).

---

### Task 1: Champ `seenByRecipientAt` sur `Types::MessageType`

**Files:**
- Modify: `app/graphql/types/message_type.rb` (ajout d'un `field` après `discarded_at`, ligne ~8)
- Modify: `app/graphql/schema.graphql` (régénéré, type `Message` ~ligne 4414)
- Test: `spec/graphql/dossier_spec.rb` (nouveau `describe` + nouvelle constante de requête)

**Interfaces:**
- Consumes: rien (colonne `seen_by_recipient_at` déjà présente sur `Commentaire`, indexée).
- Produces: champ GraphQL `Message.seenByRecipientAt: ISO8601DateTime` (nullable), consommé par les clients API externes.

- [ ] **Step 1: Écrire le test qui échoue**

Dans `spec/graphql/dossier_spec.rb`, ajouter la constante de requête à la suite des autres constantes `DOSSIER_WITH_*_QUERY` (après `DOSSIER_WITH_MESSAGE_QUERY`, vers la ligne 712) :

```ruby
  DOSSIER_WITH_MESSAGE_SEEN_QUERY = <<-GRAPHQL
  query($number: Int!) {
    dossier(number: $number) {
      messages {
        body
        seenByRecipientAt
      }
    }
  }
  GRAPHQL
```

Puis ajouter le bloc de test juste après le `describe 'dossier with message with no attachments'` (vers la ligne 421) :

```ruby
  describe 'dossier with message read state' do
    let(:dossier) { create(:dossier, :en_construction) }
    let(:query) { DOSSIER_WITH_MESSAGE_SEEN_QUERY }
    let(:variables) { { number: dossier.id } }

    context 'when the message has not been read' do
      before { create(:commentaire, dossier: dossier, seen_by_recipient_at: nil) }

      it { expect(data[:dossier][:messages][0][:seenByRecipientAt]).to be_nil }
    end

    context 'when the message has been read by the recipient' do
      let(:seen_at) { Time.zone.parse('2026-07-20T10:00:00Z') }

      before { create(:commentaire, dossier: dossier, seen_by_recipient_at: seen_at) }

      it { expect(data[:dossier][:messages][0][:seenByRecipientAt]).to eq('2026-07-20T10:00:00Z') }
    end
  end
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `bundle exec rspec spec/graphql/dossier_spec.rb -e "dossier with message read state"`
Expected: FAIL — erreur GraphQL « Field 'seenByRecipientAt' doesn't exist on type 'Message' » (les deux exemples échouent).

- [ ] **Step 3: Ajouter le champ dans `Types::MessageType`**

Dans `app/graphql/types/message_type.rb`, ajouter après la ligne `field :discarded_at, ...` :

```ruby
    # pf: expose l'instant de lecture par le destinataire — permet à un process
    # externe de déclencher un délai à partir de la lecture (ex. délai de recours).
    # Colonne upstream (seen_by_recipient_at), exposition GraphQL PF.
    field :seen_by_recipient_at, GraphQL::Types::ISO8601DateTime, null: true,
      description: "Date et heure à laquelle le destinataire a ouvert la messagerie contenant ce message (null si non lu). Pour un message envoyé par un instructeur, le destinataire est l'usager."
```

Aucune méthode de résolution à écrire : le nom correspond à la colonne `Commentaire#seen_by_recipient_at`, le résolveur par défaut suffit.

- [ ] **Step 4: Lancer le test pour vérifier qu'il passe**

Run: `bundle exec rspec spec/graphql/dossier_spec.rb -e "dossier with message read state"`
Expected: PASS (2 examples, 0 failures).

- [ ] **Step 5: Régénérer le schéma GraphQL figé**

Run: `bin/rails graphql:schema:dump`
Expected: `app/graphql/schema.graphql` modifié — le type `Message` contient désormais, dans l'ordre alphabétique des champs, `seenByRecipientAt: ISO8601DateTime` avec sa description. Vérifier le diff :

Run: `git diff --stat app/graphql/schema.graphql`
Expected: 1 file changed, insertions correspondant au champ + description (aucune autre modification de type).

- [ ] **Step 6: Vérifier l'absence de régression sur les tests GraphQL messages**

Run: `bundle exec rspec spec/graphql/dossier_spec.rb`
Expected: PASS (tous les exemples verts, y compris les `describe` existants sur `messages`).

- [ ] **Step 7: Commit**

```bash
git add app/graphql/types/message_type.rb app/graphql/schema.graphql spec/graphql/dossier_spec.rb
git commit -m "$(cat <<'EOF'
feat(pf): expose Message.seenByRecipientAt dans l'API GraphQL

Permet à un process externe de déclencher un délai à partir de la lecture
d'un message par l'usager (ex. délai de recours). Exposition PF d'une
colonne upstream, aucun changement au marquage « lu ».

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Validation finale (après la tâche)

- [ ] `bundle exec rspec spec/graphql/dossier_spec.rb` vert.
- [ ] `bundle exec rails lint` (ou `bundle exec rubocop app/graphql/types/message_type.rb`) sans nouvelle offense.
- [ ] `git diff app/graphql/schema.graphql` ne contient QUE l'ajout de `seenByRecipientAt` sur `Message`.
- [ ] Le tag `# pf:` est présent au-dessus de la déclaration du champ.

## Hors périmètre (rappel spec)

- B2 (requête « messages lus depuis X ») — chantier séparé conditionnel.
- Toute logique de délai / action / relance — process externe (robot).
- Traçage de l'identité du lecteur (titulaire vs invité) — non couvert, indistinguable par design.
