# Cadrage — Demande d'avis à un organisme : tags de destinataires + délégation

Statut : NOTE DE CADRAGE (backing doc des issues GitHub #à venir)
Date : 2026-06-24
Auteur : clautier@idt.pf

## Point de départ

Demande brute d'un instructeur :

> Rajouter une colonne dans la liste des experts pour identifier le service et
> l'île concernée (« DAG Tubuai », « CAU Tubuai », « CMQ Hiva Oa »).

Observations de terrain qui ont fait évoluer le cadrage :

- les instructeurs maintiennent des **fiches Excel** des experts possibles
  (friction réelle d'identification + réutilisation) ;
- la **responsabilité de répondre est dans le service destinataire**, pas dans le
  service source.

## Faits techniques (vérifiés dans le code)

- **Demande à plusieurs personnes : déjà supportée.** `app/models/avis.rb` →
  `attr_accessor :emails`, *« The form allows submitting avis requests to several
  emails at once »*. N mails → N `Avis`, chacun son lien, n'importe qui répond.
- **Un expert EST un `User`** (`Expert#email → user.email`). Pas de notion de
  service, d'île, de groupe ni de tag.
- **Aucun transfert/délégation d'avis** n'existe.
- Le modèle `Service` est rattaché à un `administrateur` (service **source**),
  inutilisable comme « organisme destinataire ».

## Deux axes ORTHOGONAUX

Le besoin se découpe en deux axes indépendants, livrables séparément.

### Axe A — Tags de destinataires (côté source)  → Issue 1, actionnable

Étiqueter et réutiliser un ensemble de destinataires, et afficher l'origine sur
la réponse.

- **Périmètre du tag : la procédure** (donnée partagée dans l'équipe, ni perso ni
  cross-org).
- Réutilise le multi-mail existant : le tag **préremplit** le champ `emails`.
- **Duo de traçabilité** affiché sur la liste d'avis et sur la réponse :
  *origine (le tag que j'ai posé)* + *répondeur nommé*. Deux infos distinctes :
  l'origine me renseigne sans connaître la personne, le répondeur assure
  l'imputabilité.
- Option intégrable (pas une issue séparée) : « 1 réponse parmi N suffit →
  arrêt des relances ». Le tag fournit le *handle* pour grouper les avis ;
  déclenchement **explicite**, jamais auto-clôture aveugle, répondeur toujours
  connu.
- **Absorbe la demande brute** (colonne service/île) : on identifie par le tag
  plutôt qu'en annotant chaque expert. À acter pour ne pas livrer les deux.

Données : stocker des **références user/expert, pas des chaînes mail**. Un
expert étant un user, un changement de mail du même agent ne casse rien (le bug
des `accredited_users` du visa vient justement du stockage de chaînes mail).
Angle mort mineur : une adresse encore sans compte reste une chaîne jusqu'à
création du `User` (résolution à la volée comme aujourd'hui).

### Axe B — Délégation / responsabilité côté destinataire  → Issue 2, brouillon

Permettre au service destinataire de porter la responsabilité de la réponse.

- On cible les **secrétariats / adresses génériques** des services, qui
  dispatchent. L'adresse générique est **stable** (ne part pas en mutation).
- Le service cible **décide** : répondre lui-même via son adresse générique, ou
  déléguer à une personne nommée. **Le choix du point d'entrée appartient au
  destinataire, donc la responsabilité aussi.**
- Net-neuf : transfert/redirection d'avis + points d'entrée désignés +
  traçabilité du canal.

## Imputabilité — contrainte transverse

Règle : **pas d'anonymat subi ; l'imputabilité doit être explicite et assumée.**
Deux formes légitimes :

1. **réponse nominative** (personne physique) ;
2. **réponse institutionnelle via une adresse désignée** que le service a choisie
   comme sa voix → le service assume, acte administratif valable.

Ce qui est écarté : le modèle « boîte partagée anonyme » où N membres répondent
derrière une adresse et où la plateforme **perd** qui a répondu (anonymat subi,
juridiquement faible). Exigence technique : tracer le canal
(« rendu via l'adresse désignée X du service Y »).

## Découpage en issues

| Issue | Axe | Statut | Dépendances |
|-------|-----|--------|-------------|
| 1 | Tags de destinataires (procédure) | **Actionnable** | aucune (réutilise le multi-mail) |
| 2 | Délégation côté destinataire | **Brouillon** (`on hold`) | design + maturité des destinataires sur la plateforme |

Asymétrie assumée : Issue 1 est prête à construire ; Issue 2 est une issue de
suivi/discussion tant que la maturité des destinataires n'est pas tranchée.
Issue 2 réutilise le duo de traçabilité d'Issue 1 mais n'en dépend pas
strictement.

## Question ouverte gouvernant l'Issue 2

À quel point les services destinataires sont-ils déjà présents et actifs sur la
plateforme en PF ?
- « un contact unique qui re-dispatche par mail hors plateforme » → le MVP se
  réduit à *adresser à un contact désigné + tracer le canal* ;
- plusieurs comptes experts actifs → la délégation/transfert prend tout son sens.

## Fichiers repères

- `app/models/avis.rb` — `attr_accessor :emails`, multi-mail déjà supporté
- `app/models/expert.rb` — expert = wrapper sur `User`
- `app/models/experts_procedure.rb` — lien expert ↔ procédure
- `app/views/instructeurs/dossiers/avis_new.html.haml` — formulaire de demande
- `app/views/instructeurs/avis/_sidemenu.html.haml` — liste des avis
