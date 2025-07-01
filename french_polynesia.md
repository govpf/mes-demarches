This journal lists modifications built on top of demarches-simplifiees.

# champs specifiques à la Polynésie française

| Champ                    | Label                                                                                                                                                                 |
|--------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Numero DN                | A way to enter a DN number composed of two fields : a number and date of birth                                                                                        |
| commune de Polynésie     | dropdown list of french Polynesia cities with island & archipel                                                                                                       |
| code postal de Polynésie | dropdown list of french postal codes                                                                                                                                  |
| nationalites             | dropdown list of nationalities                                                                                                                                        |
| te_fenua                 | map of polynesia using OpenLayer as a foundation                                                                                                                      |
| Visa                     | Checkbox accessible to predefined list of people. When checked, Visa records who checked the visa and disable all fields above in the current level 1 header section. |
|                          | Admin may set min,max limits                                                                                                                                          |

# Différences fonctionnelles avec démarches simplifiées

| date      | titre                               | description                                                                                                                                                                                   |
|-----------|-------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| -         | Siret vs Numero TAHITI              | Le numéro TAHITI est l'équivalent français du numéro Siren. Pour l'instant le numéro Tahiti est considéré comme un numéro Siret et tooute l'interface est changées en conséquence.            |
| -         | Lien dans les commentaires          | Les liens envoyés par les instructeurs dans les commentaires sont directement clicables                                                                                                       |
| -         | Integer, Decimal, Date              | L'administrateur a la possibilité de définir des valeurs minimales et maximales pour les champs Integer, Decimal et Date.                                                                     |
| -         | Description des champs              | La description des champ peut contenir des sous-listes à des listes                                                                                                                           |
| -         | Description des champs              | La description d'un champ peut contenir les balises des balises <img>, <a>, <font>, <ol>, <ul>,<b>,<u>,<i> pour insérer des images, liens, listes, et formater le texte                       |
| -         | Connexion usager                    | L'usager peut se connecter via Google, Microsoft ou Tatou. C'est une généralisation de la connexion France Connect.                                                                           |
| -         | Complexité du mot de passe          | Les trois roles ont un niveau de complexite pour le mot de passe: Usager => 2, Instructeur => 3, Administrateur => 4                                                                          |
| -         | Connexion Microsoft                 | Les agents de l'administration de la Polynésie etant sous Office, la connexion via Microsoft est autorisée pour les comptes instructeur et administrateur                                     |
| -         | GraphQL Assigner Instructeur        | Il est possible d'assigner un dossier à un instructeur                                                                                                                                        |
| -         | GraphQL Modifier annotation         | Il est possible de modifier une liste déroulante, l'email ou un téléphone                                                                                                                     |
| -         | GraphQL Ajouter piece justificative | Il est possible d'ajouter une piece justificative à un champ                                                                                                                                  |
| -         | Mails images                        | Il est possible d'insérer des liens <img> et <a> dans les mails officiels d'une démarche                                                                                                      |
| -         | SendInBlue                          | La suppression des mails plus vieux que 6 mois est différente (à creuser)                                                                                                                     |
| -         | Publication d'une démarche          | Un mail est toujours envoyé à l'équipe lors de la publication d'une démarche (supprimé dans DS)                                                                                               |
| -         | Normalisation Nom/Prénom            | Le NOM et le PRENOM demandé au début du formulaire sont normalisés.                                                                                                                           |
| -         | Affichage des blocs répétitifs      | Les blocs s'affichent sous forme de tableau                                                                                                                                                   |
| -         | Attestation : PJ                    | Dans les attestations, les PJ s'affichent comme des liens par défaut et une icone est affiché pour les images                                                                                 |
| 11/4/2024 | Description des champs              | La fonte est légèrement plus grande pour être lisible sur téléphone                                                                                                                           | 
| 11/4/2024 | Télécharger le PDF                  | Le lien en bas du formulaire permettant de télécharger le PDF est moins visible car les usagers ont tendance à l'utiliser même quand ils remplissent le formulaire en ligne                   |
| 23/5/2024 | EQUIPE_EMAIL                        | Mail not removed as it is used to communicate on published procedures                                                                                                                         |
| 23/5/2024 | Connecté via                        | Le mail de l'usager en haut à droite affiche quel fournisseur d'identité a servi à connecter l'usager                                                                                         |

# Commentaires techniques dans le code (# pf)

Cette section documente les modifications techniques spécifiques à la Polynésie française identifiées dans le code par des commentaires `# pf`.

## Modèles et structures de données

### Modèle Champ (`app/models/champ.rb:79`)
- Délégation des méthodes spécifiques PF (accredited_user_list, visa?, table_id) vers type_de_champ

### Modèle GeoArea (`app/models/geo_area.rb`)
- **Ligne 214, 219** : Champs `commune_associee` et `ile` spécifiques à la Polynésie française

### Modèle User (`app/models/user.rb:238`)
- Gestion du France Connect quand l'utilisateur s'est connecté avec un mot de passe régulier

## Contrôleurs

### CommencerController (`app/controllers/users/commencer_controller.rb:40`)
- Gestion de la redirection après connexion sociale (Google, France Connect, etc.)

### PieceJustificativeController (`app/controllers/champs/piece_justificative_controller.rb`)
- **Ligne 5** : Redirection des anciens liens PF (paramètre h) vers les nouvelles routes
- **Ligne 77** : Migration prévue après le 01/09/2025 pour l'accès par dossier_id uniquement

## GraphQL

### MutationType (`app/graphql/types/mutation_type.rb:19`)
- Section dédiée aux mutations spécifiques PF

### Types GeoArea
- **ParcelleCadastraleType** : Champs `commune_associee` et `ile` pour la Polynésie française
- **SelectionUtilisateurType** : Champs géographiques spécifiques PF

## Configuration

### Routes (`config/routes.rb:279`)
- Configuration des routes pour le référentiel configurable (table row selector)

### Application (`config/application.rb:46`)
- Configuration de la sanitisation HTML pour autoriser les balises `<a>`, `<font>` et `<table>`

## Types de champ

### PieceJustificativeTypeDeChamp (`app/models/types_de_champ/piece_justificative_type_de_champ.rb:10`)
- Autorisation de référencement des PJ dans les templates

### SiretTypeDeChamp (`app/models/types_de_champ/siret_type_de_champ.rb:4`)
- Les champs commune, code postal, département, région ne sont pas remplis pour les Numéros Tahiti

### DecimalNumberChamp (`app/models/champs/decimal_number_champ.rb:7`)
- Optimisation des messages d'erreur pour éviter les erreurs "trois chiffres" avec des caractères non numériques

## API Enterprise Token (`app/models/api_entreprise_token.rb`)
- **Lignes 11, 19, 24** : Gestion gracieuse de l'absence de token entreprise

## Spécificités techniques des tests

### Affichage des PJ (`spec/models/champ_spec.rb:240,254`)
- Les pièces justificatives s'affichent sous forme de liens

### RepetitionChamp (`spec/models/champs/repetition_champ_spec.rb:25`)
- Version modifiée retournant un SafeBuffer incompatible avec tiptap_node

### Helpers système (`spec/support/system_helpers.rb:23`)
- Attente nécessaire pour l'envoi des mails

### Tests système
- **BrouillonSpec** : Adaptations pour les fonctionnalités et données géographiques PF
- **DropdownSpec** : Attente pour les contrôleurs Stimulus connectés
- **InstructeurDossiersControllerSpec** : Comportements différents de DS principal
- **ProcedureCloningSpec** : Calcul de chemin par défaut différent
- **EPCIChampSpec** : Modification pour les champs EPCI optionnels
- **ComponentSpecs** : Gestion des feature flags et comportements de formatage spécifiques

## Résumé par catégorie

1. **Données géographiques** : Champs personnalisés pour la Polynésie (ile, commune_associee)
2. **Authentification** : Gestion des connexions sociales et intégration France Connect
3. **Gestion des fichiers** : Traitement des PJ et support des liens legacy
4. **Intégration API** : Validation des tokens entreprise avec gestion d'erreur gracieuse
5. **Interface utilisateur** : Sanitisation HTML, validation de formulaires, personnalisations d'affichage
6. **Configuration** : Configuration des routes pour les données référentielles
7. **Tests** : Adaptations des tests pour les fonctionnalités spécifiques PF


