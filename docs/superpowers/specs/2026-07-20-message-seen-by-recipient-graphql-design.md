# Exposition GraphQL de l'instant de lecture d'un message (`seenByRecipientAt`)

**Date :** 2026-07-20
**Statut :** design validé, prêt pour plan d'implémentation
**Périmètre :** Phase 1 uniquement (voir « Hors périmètre »)

## Problème / besoin

On veut pouvoir **déclencher une action après un délai qui démarre à la lecture, par
l'usager, d'un message de la messagerie** d'un dossier (ex. : délai de contestation
d'un état des sommes dues envoyé en cours d'instruction ; le dossier ne change pas
d'état mais l'usager a un mois pour réagir).

La logique métier (durée du délai, jours fériés PF, action à l'échéance, relances) est
volatile et n'a pas sa place dans un fork d'outil générique. Elle vivra dans un
**process externe** (robot / inspecteur-mes-demarches) qui pilote le timer et l'action.

La seule information que ce process externe ne peut pas reconstituer, et que
mes-demarches détient, est **l'instant de lecture** d'un message. Or l'API GraphQL ne
l'expose pas aujourd'hui.

## État des lieux (code existant)

- Modèle `Commentaire` (`app/models/commentaire.rb`) : colonne `seen_by_recipient_at`
  (datetime, nullable), **indexée** (`index_commentaires_on_seen_by_recipient_at`).
- Marquage « lu » :
  - `Commentaire.mark_instructeur_messages_as_seen(dossier)` — appelé quand l'usager
    ouvre l'onglet messagerie (`Users::DossiersController#messagerie`,
    `users/dossiers_controller.rb:115`). Marque **tous** les messages instructeur non
    lus du dossier via `update_all`.
  - `Commentaire.mark_usager_messages_as_seen(dossier)` — symétrique, côté instructeur
    (`instructeurs/dossiers_controller.rb:613`).
- Affichage UI « Lu / Non lu » : `app/components/dossiers/message_component/` (feature
  **upstream**, arrivée via le tag `2025-11-03-03`).
- Type GraphQL `Types::MessageType` (`app/graphql/types/message_type.rb`) : expose
  `email`, `body`, `createdAt`, `discardedAt`, `attachments`, `correction`.
  **N'expose pas** `seen_by_recipient_at`.

### Sémantique du signal (validée)

- L'email de notification d'un nouveau message (`notify_new_answer`) **ne contient pas
  le corps** du message pour un dossier soumis (cas non-brouillon) : il pointe vers la
  messagerie. Donc « l'usager n'a pas ouvert la messagerie » ⇒ « l'usager n'a pas vu le
  contenu ». `seen_by_recipient_at` est donc un vrai signal « le destinataire a accédé
  au contenu », pas juste « a ouvert l'app ».
- Réserves (à porter côté robot, pas de correction ici) :
  - Le marquage porte sur **tous** les messages du dossier à l'ouverture de l'onglet,
    pas message par message. Ce n'est **pas un accusé de réception formel opposable**.
  - **On ne sait jamais QUI a lu.** L'action `messagerie` est ouverte au titulaire
    **et aux invités** (`ACTIONS_ALLOWED_TO_OWNER_OR_INVITE`,
    `users/dossiers_controller.rb:16`), et le marquage (`update_all`) n'enregistre
    aucune identité. `seenByRecipientAt` signifie « quelqu'un ayant accès a ouvert la
    messagerie », jamais « qui ».
  - **Seul le titulaire est notifié par email** d'un nouveau message
    (`notify_new_answer` → `dossier.user_email_for(:notification)`,
    `dossier_mailer.rb:52`) ; les invités ne reçoivent pas cet email. Asymétrie qui en
    découle : en pratique c'est quasi toujours le titulaire qui ouvre (seul prévenu),
    mais un invité ouvrant le dossier de sa propre initiative pourrait faire passer
    `seenByRecipientAt` à non-null sans que le titulaire ait rien vu — cas de bord réel
    et **indistinguable** côté API. Cohérent avec « pas d'accusé de réception
    opposable ».
  - Le marquage utilise `update_all` ⇒ **ne bumpe pas `dossier.updated_at`** ⇒ la
    lecture n'est **pas découvrable** via `demarche.dossiers(updatedSince:)`.
    En revanche l'**envoi** d'un message bumpe `updated_at` (`Commentaire belongs_to
    :dossier, touch: true`), donc le dossier à surveiller est découvrable dès l'envoi.

## Décision d'architecture

mes-demarches se limite à **exposer le timestamp de lecture**. Le process externe :
1. découvre les dossiers à surveiller via `dossiers(updatedSince:)` (déclenché par
   l'envoi du message, qui bumpe `updated_at`) ou parce qu'il envoie lui-même le
   message ;
2. poll ces dossiers (≈ 1×/jour, le délai s'exprime en jours) pour lire
   `seenByRecipientAt` du message concerné ;
3. démarre le timer à la première valeur non nulle, puis déclenche l'action à
   l'échéance (y compris une relance via la mutation `dossierEnvoyerMessage`).

### Alternatives écartées

- **B1 — bumper `dossier.updated_at` au marquage « lu »** pour rendre la lecture
  découvrable via `updatedSince`. **Écarté** : une lecture n'est sémantiquement pas une
  modification du dossier ; pollue un signal partagé (tri « dossiers modifiés » des
  instructeurs, autres intégrations `updatedSince`) et modifie du comportement upstream.
- **B2 — requête GraphQL PF dédiée « messages lus depuis X »** (robot sans état, pas de
  poll unitaire). Propre sémantiquement et performant (colonne indexée), mais net-new
  surface PF à préserver à chaque merge `feature/bump-*`. **Reporté en Phase 2**, à ne
  faire que si le poll unitaire de la Phase 1 devient un problème de volume.

Le poll unitaire (Phase 1) est lent par nature mais suffisant pour un délai en jours ;
et le champ exposé en Phase 1 est **prérequis commun** à A et à B2.

## Changement à livrer (Phase 1)

### 1. Champ GraphQL

Dans `app/graphql/types/message_type.rb`, ajouter :

```ruby
# pf: expose l'instant de lecture par le destinataire — permet à un
# process externe de déclencher un délai à partir de la lecture (ex. recours)
field :seen_by_recipient_at, GraphQL::Types::ISO8601DateTime, null: true,
  description: "Date et heure à laquelle le destinataire a ouvert la messagerie " \
    "contenant ce message (null si non lu). Pour un message d'un instructeur, " \
    "le destinataire est l'usager."
```

Résolution : mapping direct sur `object.seen_by_recipient_at` (résolveur par défaut,
pas de méthode custom nécessaire — le nom `seen_by_recipient_at` correspond à la
colonne).

Le sens du message (qui est destinataire) se déduit côté consommateur du champ `email`
(expéditeur), déjà exposé.

### 2. Schéma figé

Régénérer : `bin/rails graphql:schema:dump`. Vérifier que le champ `seenByRecipientAt`
apparaît dans `app/graphql/schema.graphql` sur le type `Message`.

### 3. Tests

Spec GraphQL (dans `spec/controllers/api/v2/graphql_controller_spec.rb` ou un request
spec dédié aux messages) :
- un message non lu remonte `seenByRecipientAt: null` ;
- après `Commentaire.mark_instructeur_messages_as_seen(dossier)` (ou le flux
  équivalent), le même message remonte un timestamp ISO8601 non nul.

## Hors périmètre

- **B2** (requête « lus depuis X ») — Phase 2 conditionnelle.
- Toute **logique de délai / action / relance** — process externe.
- **Aucune** modification du marquage « lu » existant (ni `update_all`, ni `touch`).

## Risques / points de vigilance

- **Merge upstream** : le champ est tagué `# pf:`. Si upstream expose un jour
  `seenByRecipientAt`, résoudre le conflit en gardant la version upstream et en
  retirant le tag PF.
- **Confidentialité** : le champ n'ajoute pas d'accès — `MessageType.authorized?`
  contrôle déjà l'accès à la démarche. Aucun nouveau vecteur d'exposition.
