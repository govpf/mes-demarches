
# GEMINI.md - Analyse Technique et Sémantique du Projet "Mes Démarches"

Ce document décrit l'architecture technique, les concepts métiers et le fonctionnement général du projet `mes-demarches`. Il est généré automatiquement par analyse du code source.

## 1. Vue d'Ensemble du Projet

**Objectif :** `Mes-Démarches.gov.pf` est le portail de dématérialisation des démarches administratives pour les usagers et les administrations de Polynésie Française. Il s'agit d'un fork du projet `demarches-simplifiees.fr`.

**Fonctionnement général :**
1.  Une **administration** crée et publie une **démarche** (procedure) en ligne via une interface dédiée.
2.  Un **usager** (particulier ou entreprise) remplit le formulaire de la démarche, joint des pièces justificatives et soumet son **dossier**.
3.  Des **agents instructeurs**, regroupés en **groupes**, sont notifiés et traitent le dossier via un back-office. Ils peuvent échanger avec l'usager, demander des avis à des **experts** et rendre une décision.
4.  L'usager est notifié de l'avancement et de la conclusion de son dossier.

---

## 2. Stack Technique

Le projet s'appuie sur une architecture Ruby on Rails avec un frontend moderne géré par Vite.

### **Backend**
*   **Framework :** Ruby on Rails 7
*   **Langage :** Ruby
*   **Base de données :** PostgreSQL avec l'extension PostGIS pour les données géographiques.
*   **Tâches de fond :** Sidekiq (avec Redis), en cours de migration depuis Delayed Job.
*   **API :**
    *   GraphQL (principale)
    *   API REST pour certaines ressources et pour des webhooks.
*   **Authentification :**
    *   `devise` pour l'authentification classique des utilisateurs.
    *   Intégration avec des fournisseurs d'identité : FranceConnect, AgentConnect, SAML, et OAuth2 (Google, Microsoft, etc.).
*   **Autorisations :** `pundit` pour la gestion des droits par rôle.
*   **Stockage de fichiers :** Active Storage, configuré pour utiliser OpenStack ou AWS S3.
*   **Tests :** RSpec, Capybara, FactoryBot.

### **Frontend**
*   **Intégration :** Vite.js (`vite_rails`).
*   **Framework JS :** React.
*   **Librairies JS Clés :**
    *   `@hotwired/turbo` & `@hotwired/stimulus` pour la navigation et l'interactivité.
    *   `@gouvfr/dsfr` : Système de Design de l'État Français, pour l'interface utilisateur.
    *   `maplibre-gl` pour la cartographie.
    *   `tiptap` pour l'édition de texte riche.
    *   `chartkick` pour la génération de graphiques.
*   **Gestion des dépendances :** Bun (via `bun.lock`).
*   **Qualité de code :** ESLint et Prettier.

### **Infrastructure & Déploiement**
*   **Conteneurisation :** Docker (`Dockerfile`, `docker-compose.yml`).
*   **Dépendances système :** PostgreSQL, Redis, ImageMagick.
*   **Monitoring :** Skylight, Sentry, et Yabeda (pour les métriques Prometheus).

---

## 3. Architecture et Concepts Sémantiques

L'application est structurée autour de modèles de données qui représentent les concepts clés du domaine administratif.

### **Modèles de Données Principaux**

| Modèle (Table)                  | Description                                                                                                                            | Relations Clés                                                                                             |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `Procedure` (`procedures`)      | **La Démarche :** Le formulaire et le processus définis par une administration. Contient les champs, les règles, les pièces à joindre. | A plusieurs `dossiers`, `groupe_instructeurs`, `types_de_champ`. Appartient à un `service`.                |
| `Dossier` (`dossiers`)          | **La Demande :** La soumission d'un usager à une démarche. Contient les données saisies et suit un cycle de vie (état).                 | Appartient à un `user`, une `procedure` (via `revision`), et est traité par un `groupe_instructeur`.      |
| `User` (`users`)                | **L'Utilisateur :** Entité centrale pour toute personne interagissant avec le système. Géré par Devise.                                | Peut être un usager, `administrateur`, `instructeur`, `expert`, `gestionnaire`.                            |
| `Champ` (`champs`)              | **Le Champ de Données :** Une donnée spécifique remplie par un usager dans un dossier.                                                 | Appartient à un `dossier` et à un `type_de_champ`.                                                         |
| `TypeDeChamp` (`types_de_champ`) | **La Définition du Champ :** La structure d'un champ pour une démarche (libellé, type, obligatoire, etc.).                               | Appartient à une `procedure` (via `procedure_revisions`).                                                  |
| `GroupeInstructeur`             | **Le Groupe d'Instructeurs :** Une équipe d'agents responsables du traitement des dossiers d'une ou plusieurs démarches.                | Appartient à une `procedure`, a plusieurs `instructeurs`.                                                  |
| `Commentaire` (`commentaires`)  | **Le Message :** Utilisé pour la messagerie interne à un dossier, entre les instructeurs, les experts et l'usager.                     | Appartient à un `dossier`.                                                                                 |
| `Avis` (`avis`)                 | **La Demande d'Avis :** Une sollicitation formelle d'un expert sur un dossier.                                                         | Appartient à un `dossier` et est lié à un `expert`.                                                        |

### **Rôles des Utilisateurs**

Le système définit plusieurs rôles, chacun avec des permissions spécifiques :

*   **Usager (`user`) :** Le citoyen ou l'entreprise qui soumet des dossiers.
*   **Administrateur (`administrateur`) :** L'agent qui crée, configure et gère les démarches (`procedures`).
*   **Instructeur (`instructeur`) :** L'agent qui traite les dossiers (`dossiers`) qui lui sont assignés via son groupe.
*   **Expert (`expert`) :** Une personne sollicitée pour donner un avis technique ou métier sur un dossier.
*   **Gestionnaire (`gestionnaire`) :** Un rôle de supervision, souvent organisé en hiérarchie (`groupe_gestionnaires`).
*   **Super Admin (`super_admin`) :** Développeur ou administrateur système avec un accès complet pour la maintenance.

### **Structure des Routes (`config/routes.rb`)**

Les routes sont organisées par namespaces correspondant aux rôles, ce qui isole les fonctionnalités :
*   `/` (root) : Routes publiques et pour les usagers (`dossiers`, `profil`, etc.).
*   `/admin` : Espace des **administrateurs** pour la gestion des `procedures`.
*   `/instructeur` : Espace des **instructeurs** pour le traitement des `dossiers`.
*   `/expert` : Espace des **experts** pour la consultation des demandes d'avis.
*   `/manager` : Espace des **super_admins** pour la supervision globale, la gestion des utilisateurs et l'accès aux outils (Sidekiq, Flipper).
*   `/api` : Points d'accès pour les API (GraphQL et REST).

---

## 4. Flux de Travail de Développement

*   **Installation :** `bin/setup` pour installer les dépendances et configurer la base de données.
*   **Lancement local :** `bin/dev` pour lancer le serveur Rails, Vite et le worker Sidekiq.
*   **Tests :** `bin/rspec` pour lancer la suite de tests.
*   **Qualité de code :** `bin/rake lint` pour exécuter les linters (RuboCop, ESLint, etc.).
*   **Déploiement :** Le fichier `doc/DEPLOYMENT.md` contient les instructions spécifiques.

### **Processus de Release sur GitHub**

Ce processus est basé sur les instructions du fichier `CLAUDE.md`.

1.  **Préparation :**
    *   Se placer sur la branche `masterpf`.
    *   Identifier le dernier tag de release (ex: `pf-AAAA-MM-JJ`).
    *   Analyser les commits réalisés depuis ce tag.

2.  **Identifier les Releases Upstream :**
    *   Identifier précisément la ou les releases de `demarches-simplifiees.fr` qui ont été intégrées.
    *   Récupérer le contenu de ces releases depuis leur page GitHub.

3.  **Rédiger les Notes de Release :**
    *   Le titre doit être : `# Release pf-AAAA-MM-JJ`.
    *   Créer une section `## Améliorations et correctifs`.
    *   **D'abord, lister les changements spécifiques à la Polynésie :**
        *   Créer une sous-section `### Polynésie`.
        *   Utiliser un chapitre `#### Technique` pour les détails de maintenance.
        *   Lister les fonctionnalités et corrections importantes pour les utilisateurs.
    *   **Ensuite, intégrer les notes de l'upstream :**
        *   Créer une sous-section `### Intégration de la release upstream AAAA-MM-JJ-NN` pour chaque release upstream.
        *   À l'intérieur, respecter scrupuleusement les chapitres : `#### Administrateur`, `#### Instructeur`, `#### Usager`, `#### API`, `#### Technique`.
        *   Copier-coller le contenu exact de la release upstream, en conservant le format "ETQ" et les numéros d'issues.

4.  **Lister les Migrations :**
    *   Si des migrations de base de données sont incluses, les lister sous une section `## Migrations`.

5.  **Créer la Release sur GitHub :**
    *   Utiliser l'outil `gh` pour créer le tag et la release en une seule commande. La commande créera le tag `pf-AAAA-MM-JJ` sur le commit cible de la branche `masterpf`.
        ```bash
        gh release create pf-AAAA-MM-JJ --title "JJ MMM AAAA" --notes-file /chemin/vers/notes.md
        ```
        *(Note: Il est recommandé de préparer les notes dans un fichier temporaire)*

6.  **Vérification :**
    *   Vérifier que la release est bien visible sur la page des releases de GitHub. Le tag sera créé automatiquement.
