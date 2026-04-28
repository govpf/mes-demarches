# Spécification : Champ Formule

## État actuel de l'implémentation (Août 2025)

**✅ Statut : Fonctionnel en environnement de développement**
- Feature flag `formule` activé dans Flipper
- Service de calcul avec Dentaku opérationnel
- Conversion bidirectionnelle labels ↔ stable_ids implémentée
- Fonctions françaises (SOMME, SI, MOYENNE) disponibles

## Descriptif

Le champ formule permet de calculer automatiquement des valeurs **numériques ou textuelles** en fonction des champs précédents dans un formulaire. 

Basé sur l'analyse des formulaires existants en Polynésie française, cette fonctionnalité répond aux besoins concrets suivants :

**🏆 Cas d'usage prioritaires identifiés :**
- **Totaux de commande** : Quantité × Prix unitaire (très fréquent)
- **Montants avec abattements** : Réductions pour administrations publiques (-50%)
- **Calculs de délais** : Dates d'échéance, durées de traitement
- **Messages récapitulatifs** : Confirmations personnalisées avec détails calculés
- **Concaténation d'informations** : Noms complets, adresses complètes

### Fonctionnement

Un champ formule s'appuie sur les champs précédents pour effectuer ses calculs. Dans le cas d'une annotation privée, la formule peut référencer tous les champs usagers et toutes les annotations qui précèdent le champ formule.

La valeur calculée se met à jour automatiquement dès qu'un champ dépendant est modifié, en utilisant le système de conditions existant (modèle `Logic`).

### Types de formules supportées

- **Formules numériques** : calculs mathématiques, conditions retournant des nombres
- **Formules textuelles** : génération de texte, concaténation, conditions retournant du texte

## Gems à ajouter au projet

### Dentaku
```ruby
gem 'dentaku', '~> 3.5.4'
```

**Pourquoi Dentaku ?**
- Parser et évaluateur sécurisé pour formules mathématiques **et textuelles**
- Support des variables et fonctions personnalisées
- Gestion de la précédence des opérateurs et parenthèses
- Fonctions intégrées numériques (SUM, MIN, MAX, IF, etc.)
- **Fonctions intégrées textuelles (CONCAT, LEFT, RIGHT, MID, LEN, FIND, SUBSTITUTE, CONTAINS)**
- Évaluation sécurisée d'expressions utilisateur sans risques de sécurité
- Cache des AST pour de meilleures performances

## Architecture implémentée

### Système hybride labels/stable_ids

**Principe fondamental :** Les formules utilisent des **stable_ids** en interne pour garantir la robustesse, mais affichent des **labels** pour l'utilisateur.

#### **Workflow de conversion :**
1. **Interface utilisateur** : L'admin saisit `{Prix unitaire} * {Quantité}`
2. **Conversion JavaScript** : `FormulaEditorController` convertit en `{1234} * {5678}`
3. **Stockage BDD** : Expression sauvegardée avec stable_ids
4. **Calcul serveur** : `FormulaCalculationService` utilise les stable_ids
5. **Affichage retour** : Reconversion stable_ids → labels pour l'utilisateur

#### **Avantages critiques des stable_ids :**
- ✅ **Immunité au renommage** : Les formules survivent aux changements de libellés
- ✅ **Unicité garantie** : Pas de collision entre champs homonymes
- ✅ **Performance** : Résolution directe sans recherche par label
- ✅ **Traçabilité** : Identification précise des dépendances

#### **Code existant (extraits) :**
```javascript
// app/javascript/controllers/formula_editor_controller.ts
private convertToStableIds(expression: string): string {
  return expression.replace(/\{([^}]+)\}/g, (match, label) => {
    const stableId = champsMap.get(label.toLowerCase().trim());
    return stableId ? `{${stableId}}` : match;
  });
}
```

```ruby
# app/services/formula_calculation_service.rb
def resolve_field_references(expression)
  expression.gsub(/\{(\d+)\}/) do |_match|
    stable_id = $1.to_i
    champ = find_champ_by_stable_id(stable_id)
    get_champ_numeric_value(champ)
  end
end
```

## Composants techniques

### Contraintes d'ordre des variables (À IMPLÉMENTER)

**Règle fondamentale :** Une formule ne peut référencer que les champs **précédents** dans l'ordre du formulaire, exactement comme le système de conditions existant.

#### **🔒 Contraintes pour champs publics usager :**
- ✅ **Variables système** : `{Nº dossier}`, `{Date de dépôt}`, `{Demandeur}` → **Toujours disponibles**
- ✅ **Champs publics précédents** : selon `position` dans `revision_types_de_champ`
- ❌ **Champs publics suivants** : interdits (prévention références circulaires)
- ❌ **Annotations privées** : jamais accessibles depuis champs publics

#### **🔓 Contraintes pour annotations privées (accès élargi) :**
- ✅ **Variables système** : `{Nº dossier}`, `{Date de dépôt}`, `{Demandeur}` → **Toujours disponibles**  
- ✅ **TOUS les champs publics** : peu importe leur position → **Toujours accessibles**
- ✅ **Annotations privées précédentes** : selon `position` dans `revision_types_de_champ_private`
- ❌ **Annotations privées suivantes** : interdites

#### **Justification métier :**
```
📋 FORMULAIRE USAGER (public)          🏢 INTERFACE INSTRUCTEUR (privé)
┌─────────────────────────────┐        ┌─────────────────────────────┐
│ 1. Nom                      │   ──→  │ Tous champs publics         │
│ 2. Prénom                   │        │ (déjà remplis par usager)   │
│ 3. Formule: {Nom} {Prénom}  │        │                             │
│                             │        │ 1. Note interne             │
│ ❌ Ne peut PAS voir →       │        │ 2. Formule: {Nom} + {Note}  │
└─────────────────────────────┘        └─────────────────────────────┘
```

**Avantages :**
- 🔄 **Cohérence totale** avec système de conditions existant
- 🚫 **Prévention boucles infinies** : A dépend de B qui dépend de A
- 👤 **UX logique** : ordre visuel = ordre logique des calculs
- ⚡ **Performance** : calculs séquentiels sans recalculs en cascade

### Architecture : Système de colonnes avec stable_ids

**⚠️ PRINCIPE FONDAMENTAL :** Les variables utilisent les **stable_ids** en interne, jamais les labels directement.

**Pourquoi cette architecture hybride :**
- **Colonnes** : Pour identifier les variables disponibles et leurs contraintes d'accès
- **Stable_ids** : Pour référencer les champs de manière robuste et immuable
- **Labels** : Pour l'affichage utilisateur uniquement

**Justification :**
- ✅ Le système de colonnes est **plus récent** et en développement actif
- ✅ Le système de tags est en **réécriture** pour avoir une interface plus conviviale
- ✅ **Cohérence** : même nommage que l'interface de filtrage instructeur
- ✅ **Évolutivité** : nouvelles colonnes automatiquement disponibles
- ✅ **Performance** : système déjà mis en cache (`Current.procedure_columns`)

**Génération automatique des variables avec contraintes d'ordre :**
```ruby
# Dans le contrôleur de configuration du champ formule
def available_variables_for_formula(current_type_de_champ)
  current_position = current_type_de_champ.coordinate.position
  current_private = current_type_de_champ.private?
  
  # Variables système : toujours disponibles
  system_variables = @procedure.columns
    .select { |col| col.table.in?(['self', 'user', 'etablissement']) }
    .select(&:filterable?)
  
  # Variables de champs selon les règles métier
  if current_private
    # FORMULE EN ANNOTATION PRIVÉE : accès élargi
    field_variables = @procedure.columns
      .select { |col| col.table == 'type_de_champ' }
      .select { |col|
        source_tdc = find_type_de_champ_by_stable_id(col.stable_id)
        if source_tdc.public?
          true  # TOUS les champs publics toujours accessibles
        else
          # Annotations privées : seulement celles AVANT
          source_tdc.coordinate.position < current_position
        end
      }
  else
    # FORMULE EN CHAMP PUBLIC : accès restreint
    field_variables = @procedure.columns
      .select { |col| col.table == 'type_de_champ' }
      .select { |col|
        source_tdc = find_type_de_champ_by_stable_id(col.stable_id)
        # Seulement les champs publics PRÉCÉDENTS
        source_tdc.public? && source_tdc.coordinate.position < current_position
      }
  end
  
  (system_variables + field_variables).map { |col|
    {
      label: col.label,         # "Date de dépôt"
      syntax: "{#{col.label}}", # "{Date de dépôt}"  
      type: col.type,          # :datetime
      category: col.table,     # "self", "user", "type_de_champ"
      h_id: col.h_id          # Identifiant technique
    }
  }
end
```

### Autocomplétion des champs

**Stimulus Controller pour l'autocomplétion :**
```javascript
// app/javascript/controllers/formula_field_controller.js
export default class extends Controller {
  static targets = ["expression", "preview", "examples"]
  static values = { availableFields: Array }
  
  connect() {
    this.setupAutocomplete()
  }
  
  // Autocomplétion sur frappe de '{'
  handleInput(event) {
    const text = event.target.value
    const cursorPos = event.target.selectionStart
    const beforeCursor = text.substring(0, cursorPos)
    
    if (beforeCursor.endsWith('{')) {
      this.showFieldDropdown(cursorPos)
    }
  }
  
  showFieldDropdown(position) {
    const dropdown = this.createDropdown(this.availableFieldsValue)
    this.positionDropdown(dropdown, position)
  }
  
  // Insertion d'un champ sélectionné
  insertField(fieldName) {
    const textarea = this.expressionTarget
    const cursorPos = textarea.selectionStart
    const text = textarea.value
    
    // Remplace '{' par '{Nom du champ}'
    const newText = text.substring(0, cursorPos - 1) + 
                   `{${fieldName}}` + 
                   text.substring(cursorPos)
    
    textarea.value = newText
    this.validateExpression()
  }
}
```

### Banque d'exemples

**Configuration YAML :**
```yaml
# config/formula_examples.yml - voir section précédente
```

**Helper pour charger les exemples :**
```ruby
# app/helpers/formula_examples_helper.rb
module FormulaExamplesHelper
  def formula_examples
    @formula_examples ||= YAML.load_file(
      Rails.root.join('config', 'formula_examples.yml')
    )
  end
  
  def examples_by_category(category)
    formula_examples[category.to_s] || []
  end
end
```

**Composant Vue pour la popup d'exemples :**
```erb
<!-- app/views/shared/_formula_examples_modal.html.erb -->
<div class="formula-examples-modal" data-formula-field-target="examples">
  <div class="examples-grid">
    <% %w[financial temporal text quantity].each do |category| %>
      <div class="examples-category">
        <h4><%= t("formula_examples.#{category}.title") %></h4>
        <% examples_by_category(category).each do |example| %>
          <div class="example-item" 
               data-action="click->formula-field#insertExample"
               data-formula="<%= example['formula'] %>">
            <strong><%= example['name'] %></strong>
            <code><%= truncate(example['formula'], length: 40) %></code>
            <small><%= example['description'] %></small>
          </div>
        <% end %>
      </div>
    <% end %>
  </div>
</div>
```

## Étapes de développement

### ✅ Étapes TERMINÉES (implémentation actuelle)

#### Étape 1 : Fondations techniques ✅
**Implémentation complète du champ formule fonctionnel**

**Réalisé :**
- ✅ **Modèle** : `formule: 'formule'` dans TypeDeChamp
- ✅ **Classes** :
  - `TypesDeChamp::FormuleTypeDeChamp` avec validation
  - `Champs::FormuleChamp` avec calcul automatique
- ✅ **Service de calcul** : `FormulaCalculationService` avec Dentaku
- ✅ **Feature flag** : Activé dans Flipper
- ✅ **Conversion labels/stable_ids** : JavaScript bidirectionnel
- ✅ **Fonctions françaises** : SOMME, SI, MOYENNE, ARRONDI
- ✅ **Détection références circulaires**

#### Étape 2 : Interface d'administration ✅
**Interface de configuration implémentée**

**Réalisé :**
- ✅ **Interface épurée** dans le flux d'édition des champs
- ✅ **Textarea** avec conversion labels/stable_ids transparente
- ✅ **Validation JavaScript** en temps réel
- ✅ **Messages localisés** (fr/en)
- ⚠️ **À améliorer** : Pas d'autocomplétion ni banque d'exemples

**Interface proposée :**
```
┌─ Champ Formule ──────────────────────────┐
│ Libellé : [Total commande_________]      │
│                                          │
│ Expression : [________________________] │
│              👁️ [Exemples] 🔍 [Aide]     │
│                                          │
│ ☑️ Obligatoire  ⚙️ Plus d'options        │
└──────────────────────────────────────────┘
```

**Critères d'acceptation :**
- Interface sobre qui s'intègre naturellement dans l'éditeur
- Accès aux exemples et aide sans quitter le contexte
- Autocomplétion fluide des noms de champs
- Validation immédiate sans encombrement visuel

#### Étape 3 : Interface usager ✅
**Affichage en lecture seule implémenté**

**Réalisé :**
- ✅ **Composant** `FormuleComponent` pour l'affichage
- ✅ **Valeur calculée** affichée automatiquement
- ✅ **Messages d'erreur** clairs si calcul impossible
- ✅ **Export** : Support API v1, v2 et export CSV

### 🚀 Étapes À RÉALISER (prioritaires)

#### Étape 4 : Contraintes d'ordre et contexte ⚠️ CRITIQUE
**En tant que système, je dois respecter les mêmes contraintes que les conditions**

**Tâches prioritaires :**
- [ ] **Validation des stable_ids accessibles** selon position
- [ ] **Règles contexte public/privé** :
  - Champ public : accès aux champs publics précédents seulement
  - Annotation privée : accès à TOUS les champs publics + annotations précédentes
- [ ] **Message d'erreur explicite** si référence interdite
- [ ] **Tests de non-régression** sur formules existantes

**Implémentation suggérée :**
```ruby
# Dans TypeDeChamp ou FormulaCalculationService
def available_stable_ids_for_formula
  current_position = coordinate.position
  
  if private?
    # Annotation : tous les publics + privés précédents
    all_public_stable_ids + preceding_private_stable_ids(current_position)
  else
    # Champ public : seulement publics précédents
    preceding_public_stable_ids(current_position)
  end
end
```

#### Étape 5 : Autocomplétion et aide contextuelle
**En tant qu'administrateur, je veux découvrir facilement les variables disponibles**

**Tâches :**
- [ ] **Dropdown d'autocomplétion** sur frappe de `{`
- [ ] **Liste des variables disponibles** selon contraintes d'ordre
- [ ] **Conversion automatique** label → stable_id à la sélection
- [ ] **Indicateur de type** (text, number, date) pour chaque variable

**Code à ajouter dans FormulaEditorController :**
```typescript
// Enrichir avec les variables disponibles selon contexte
static values = {
  availableVariables: Array, // Variables avec stable_id + label + type
  context: String // 'public' ou 'private'
}

private showAutocomplete() {
  const variables = this.availableVariablesValue.filter(v => {
    // Filtrer selon contraintes d'ordre et contexte
    return this.canAccessVariable(v);
  });
  
  this.displayDropdown(variables);
}

### Étape 5 : Recalcul automatique (Sprint 3) 
**En tant qu'usager, je veux que mes calculs se mettent à jour automatiquement**

**Approche Stimulus légère :**
```javascript
// Recalcul sur changement de champ
export default class extends Controller {
  recalculateFormulas() {
    // Détecte les champs référencés modifiés
    // Recalcule uniquement les formules concernées
    // Update via Turbo Stream
  }
}
```

**Tâches priorisées :**
- [ ] Détection de changement sur les champs sources
- [ ] Recalcul différentiel (pas tout recalculer)
- [ ] Update de l'affichage via Turbo
- [ ] Protection contre les boucles infinies

**Critères pratiques :**
- Latence < 200ms pour recalcul simple
- Support jusqu'à 5 formules par formulaire
- Fonctionnel sur mobile

### Étape 6 : Annotations privées (Sprint 4)
**En tant qu'agent, je veux automatiser mes calculs internes**

**Cas d'usage agent :**
- Calcul automatique de montants à facturer
- Score d'éligibilité automatique
- Récapitulatifs pour la décision

**Tâches simples :**
- [ ] Activer le type formule dans les annotations
- [ ] Accès à tous les champs usager depuis les annotations
- [ ] Sécurité : usager ne voit pas les formules privées
- [ ] Test workflow : création → instruction → décision

**Priorité réduite :** Peut être reporté si le MVP utilisateur fonctionne bien

### Étape 7 : Tests et qualité (transverse)
**Intégré dans chaque sprint pour livrer de la qualité**

**Tests essentiels par sprint :**

**Sprint 1 :**
- [ ] Tests unitaires : `FormuleChamp#compute_value`
- [ ] Tests d'intégration : Création + calcul basique
- [ ] Tests d'erreur : Syntaxe invalide, champ inexistant

**Sprint 2-3 :**
- [ ] Tests UI : Interface sobre, popup exemples
- [ ] Tests JavaScript : Autocomplétion, insertion
- [ ] Tests de performance : 100ms max pour recalcul

**Sprint 4 :**
- [ ] Tests d'acceptation : Workflow complet usager/agent  
- [ ] Tests de régression : Compatibilité formulaires existants

**Objectif pragmatique :** 80% de couverture sur les chemins critiques

### Étape 8 : Banque d'exemples et autocomplétion
**En tant qu'administrateur, je veux accéder facilement aux formules courantes et aux champs disponibles**

**Tâches :**
- [ ] Créer le fichier de configuration `formula_examples.yml`
- [ ] Implémenter le Stimulus controller pour l'autocomplétion
- [ ] Développer la popup d'exemples avec catégorisation
- [ ] Ajouter la détection de frappe `{` pour l'autocomplétion
- [ ] Implémenter l'insertion automatique des exemples
- [ ] Créer les styles CSS pour une interface sobre

**Critères d'acceptation :**
- Frappe de `{` déclenche l'autocomplétion des champs
- Popup d'exemples accessible via bouton discret
- Insertion d'exemple adapte automatiquement aux champs disponibles
- Interface reste légère dans le contexte d'édition de formulaire

### Étape 9 : Documentation contextuelle
**En tant qu'utilisateur, je veux une aide immédiate sans quitter mon contexte**

**Tâches :**
- [ ] Tooltip sur les fonctions Dentaku lors de la frappe
- [ ] Aide contextuelle intégrée (pas de documentation externe)
- [ ] Exemples dynamiques basés sur les champs disponibles
- [ ] Messages d'erreur clairs et actionables

**Critères d'acceptation :**
- Aide accessible sans navigation externe  
- Exemples adaptés au contexte du formulaire en cours
- Messages d'erreur proposent des solutions
- Formation de 5 minutes suffit pour un administrateur

## Roadmap actualisée (post-implémentation de base)

### ✅ Phase 1 : MVP (TERMINÉ)
- Base fonctionnelle avec Dentaku
- Conversion labels/stable_ids
- Interface d'administration minimale
- Affichage usager en lecture seule

### 🚀 Phase 2 : Contraintes métier (2 jours) - PRIORITÉ HAUTE
- **Jour 1** : Implémenter les contraintes d'ordre
  - Validation des stable_ids selon position
  - Règles différenciées public/privé
  - Tests unitaires complets
- **Jour 2** : Messages d'erreur et tests d'intégration
  - Messages explicites pour références interdites
  - Tests sur procédures complexes

### 📝 Phase 3 : Amélioration UX (2-3 jours)
- **Autocomplétion** (1 jour)
  - Dropdown des variables disponibles
  - Respect des contraintes d'ordre
  - Indicateurs de type
- **Banque d'exemples** (1 jour)
  - 15-20 formules types
  - Adaptation aux champs disponibles
  - Insertion facilitée
- **Documentation contextuelle** (0.5 jour)
  - Aide sur les fonctions françaises
  - Tooltips explicatifs

### 🔄 Phase 4 : Intégrations avancées (2 jours)
- **Recalcul automatique** via Stimulus
- **Intégration publipostage** : formules comme variables
- **Optimisations performance** : cache des calculs

**Total estimé : 6-7 jours** pour une solution complète et robuste

### Métriques de succès
- **Adoption :** 30% des nouveaux formulaires utilisent au moins 1 champ formule
- **Facilité :** 80% des administrateurs trouvent les exemples sans aide
- **Fiabilité :** 95% des formules fonctionnent du premier coup
- **Performance :** Recalcul < 100ms même avec 10 formules

## Questions et points d'attention révisés

### Choix d'architecture validés :

1. **Interface utilisateur** : Comment éviter la surcharge visuelle ?
   - ✅ **Validé** : Interface sobre, composant discret intégré
   - ✅ **Validé** : Aide accessible via boutons icônes légers
   - ✅ **Validé** : Popup d'exemples au lieu d'interface riche

2. **Approche utilisateur** : Templates vs formules libres ?
   - ✅ **Validé** : **Banque d'exemples** + liberté d'adaptation
   - ✅ **Validé** : **Autocomplétion** pour la découverte des champs
   - ✅ **Validé** : Progression : exemple → adaptation → création libre

3. **Syntaxe et référencement** :
   - ✅ **Validé** : Syntaxe Dentaku standard avec fonctions françaises
   - ✅ **Validé** : Variables `{Label de la colonne}` (système de colonnes)
   - ✅ **Validé** : Autocomplétion basée sur `procedure.columns`
   - ✅ **Validé** : Types simplifiés (tout texte, conversion auto)
   - ✅ **Validé** : Cohérence avec interface de filtrage instructeur

4. **Architecture fork** :
   - ✅ **Validé** : Constantes INSTANCE_* pour la compatibilité

5. **Performance** : Comment optimiser les recalculs pour de gros formulaires ?
   - Cache des expressions parsées
   - Calcul paresseux (lazy evaluation)
   - Éviter les recalculs en cascade

6. **Sécurité** : Quelles sont les fonctions autorisées dans les formules ?
   - Fonctions mathématiques standard
   - **Fonctions de manipulation de chaînes Dentaku**
   - Pas d'accès aux fonctions système

### Banque d'exemples (basée sur l'analyse des formulaires réels et variables de colonnes)

**Configuration de la banque d'exemples avec variables de colonnes réelles :**
```yaml
# config/formula_examples.yml
financial:
  - name: "Total simple"
    formula: "{Prix unitaire} * {Quantité}"
    description: "Calcule le montant d'une ligne de commande"
    variables: ["Prix unitaire", "Quantité"]
  - name: "Total avec abattement public"
    formula: 'SI({Type demandeur} = "Administration", {Montant} * 0.5, {Montant})'
    description: "Applique -50% pour les administrations publiques"
    variables: ["Type demandeur", "Montant"]
  - name: "Montant avec remise"
    formula: "{Montant} * (1 - {Taux remise} / 100)"
    description: "Applique un taux de remise en pourcentage"
    variables: ["Montant", "Taux remise"]

temporal:
  - name: "Délai depuis dépôt"
    formula: "AUJOURDHUI() - {Date de dépôt}"
    description: "Calcule les jours écoulés depuis le dépôt"
    variables: ["Date de dépôt"]
  - name: "Échéance automatique"
    formula: "{Date de dépôt} + {Délai jours}"
    description: "Calcule une date d'échéance à partir du dépôt"
    variables: ["Date de dépôt", "Délai jours"]
  - name: "Durée traitement"
    formula: "{Date de passage en instruction} - {Date de dépôt}"
    description: "Calcule la durée entre dépôt et instruction"
    variables: ["Date de passage en instruction", "Date de dépôt"]

text:
  - name: "Nom complet usager"
    formula: 'CONCATENER({Prénom}, " ", {Nom})'
    description: "Combine prénom et nom (si particulier)"
    variables: ["Prénom", "Nom"]
  - name: "Récapitulatif dossier"
    formula: 'CONCATENER("Dossier ", {Nº dossier}, " déposé le ", {Date de dépôt})'
    description: "Message récapitulatif avec infos dossier"
    variables: ["Nº dossier", "Date de dépôt"]
  - name: "Statut conditionnel"
    formula: 'SI({Montant} > 50000, "Validation requise", "Traitement automatique")'
    description: "Message selon conditions de montant"
    variables: ["Montant"]

quantity:
  - name: "Somme de quantités"
    formula: "SOMME({Quantité 1}, {Quantité 2}, {Quantité 3})"
    description: "Additionne plusieurs champs quantité"
    variables: ["Quantité 1", "Quantité 2", "Quantité 3"]
  - name: "Moyenne"
    formula: "MOYENNE({Valeur 1}, {Valeur 2}, {Valeur 3})"
    description: "Calcule une moyenne de valeurs"
    variables: ["Valeur 1", "Valeur 2", "Valeur 3"]
```

**Interface popup d'exemples :**
```
┌─ Formules courantes ─────────────────────┐
│ 💰 Financier                             │
│   • Total simple: {Prix} * {Quantité}   │
│   • Abattement public: IF({Admin}...    │
│   • Remise: {Montant} * (1 - {Taux}..   │
│                                          │
│ ⏰ Dates & Délais                        │
│   • Délai: {Fin} - {Début}              │
│   • Échéance: {Date} + {Jours}          │
│                                          │
│ 📝 Texte & Messages                      │
│   • Nom complet: CONCAT({Prénom}...     │
│   • Récapitulatif: CONCAT("Commande...  │
│                                          │
│ [Utiliser] [Adapter] [Fermer]           │
└──────────────────────────────────────────┘
```

### Fonctions disponibles (noms français comme Excel) :

**Décision d'architecture :** Utilisation de **noms de fonctions français** (style Excel) pour une meilleure familiarité des utilisateurs français.

#### Fonctions mathématiques :
- Arithmétiques : `+`, `-`, `*`, `/`, `%`
- Comparaisons : `=`, `!=`, `<`, `>`, `<=`, `>=`
- Logiques : `ET`, `OU`, `NON`
- Conditions : `SI(condition, si_vrai, si_faux)`
- Agrégation : `SOMME()`, `MIN()`, `MAX()`, `MOYENNE()`
- Math : `ARRONDI()`, `ARRONDI.SUP()`, `ARRONDI.INF()`, `ABS()`, `RACINE()`
- Dates : `AUJOURDHUI()`, `ANNEE()`, `MOIS()`, `JOUR()`

#### Fonctions textuelles :
- Concaténation : `CONCATENER()`
- Extraction : `GAUCHE()`, `DROITE()`, `STXT()`
- Informations : `NBCAR()`, `CHERCHE()`, `TROUVE()`
- Transformation : `SUBSTITUE()`, `MAJUSCULE()`, `MINUSCULE()`

**Implémentation :** Configuration Dentaku avec alias français :
```ruby
# Configuration des fonctions françaises
Dentaku::Calculator.new.configure do |c|
  c.add_function(:si, :numeric, ->(condition, si_vrai, si_faux) {
    condition ? si_vrai : si_faux
  })
  c.add_function(:somme, :numeric, ->(*args) { args.sum })
  c.add_function(:concatener, :string, ->(*args) { args.join })
  # etc...
end
```

### Contraintes spécifiques au fork :

1. **Utilisation des constantes INSTANCE_*** :
   - `INSTANCE_TYPE_CHAMPS` : Ajout du type `formule: 'formule'`
   - `INSTANCE_TYPE_DE_CHAMP_TO_CATEGORIE` : Classification `formule: STANDARD`
   - `INSTANCE_OPTIONS` : Ajout de `formule_expression`

2. **Gestion des types simplifiée** :
   - **Toutes les références de champs retournent systématiquement du texte**
   - **Conversion automatique texte→numérique lors des opérations mathématiques**
   - **Résultat final toujours textuel (pas de type de retour à choisir)**

3. **À valider avec les utilisateurs réels** :
   - **Test d'usage** : 3 administrateurs créent un formulaire avec champ formule
   - **Métrique clé** : Temps moyen pour créer une formule de total
   - **Feedback** : Points de friction dans l'interface sobre
   - **Adoption** : Utilisation spontanée après formation de 5 minutes

### Limitations initiales réalistes :

- **Expressions limitées à 500 caractères** (largement suffisant pour 95% des cas)
- **Banque d'exemples figée** dans un premier temps (15-20 formules)
- **Résultat toujours textuel** (simplification technique)
- **Autocomplétion basique** : nom de champs uniquement (pas de fonctions)
- **Pas de formules imbriquées complexes** (garde la simplicité)

### Interface d'autocomplétion adaptative selon contexte :

```html
<!-- Dropdown d'autocomplétion avec contraintes d'ordre -->
<div class="variable-dropdown" data-context="{{public|private}}">
  <div class="category">
    <h4>📁 Variables système (toujours disponibles)</h4>
    <div class="variables">
      <div class="variable" data-label="Nº dossier" data-type="integer">Nº dossier</div>
      <div class="variable" data-label="Date de dépôt" data-type="datetime">Date de dépôt</div>
      <div class="variable" data-label="Demandeur" data-type="text">Demandeur</div>
      <div class="variable" data-label="Nom" data-type="text">Nom</div>
      <div class="variable" data-label="Prénom" data-type="text">Prénom</div>
    </div>
  </div>
  
  <!-- CONTEXTE : CHAMP PUBLIC -->
  <div class="category" data-show-if="public">
    <h4>📋 Champs précédents uniquement</h4>
    <div class="variables">
      <!-- Seulement les champs publics AVANT ce champ formule -->
      <div class="variable" data-label="Premier champ" data-type="text">Premier champ</div>
      <div class="variable" data-label="Deuxième champ" data-type="enum">Deuxième champ</div>
    </div>
    <div class="constraint-info">
      <small>⚠️ Seuls les champs situés avant ce champ formule sont disponibles</small>
    </div>
  </div>
  
  <!-- CONTEXTE : ANNOTATION PRIVÉE -->
  <div class="category" data-show-if="private">
    <h4>📋 Tous les champs usager (accès élargi)</h4>
    <div class="variables">
      <!-- TOUS les champs publics (peu importe position) -->
      <div class="variable" data-label="Premier champ" data-type="text">Premier champ</div>
      <div class="variable" data-label="Deuxième champ" data-type="enum">Deuxième champ</div>
      <div class="variable" data-label="Dernier champ" data-type="date">Dernier champ</div>
    </div>
  </div>
  
  <div class="category" data-show-if="private">
    <h4>🏢 Annotations précédentes</h4>
    <div class="variables">
      <!-- Seulement annotations privées AVANT cette formule -->
      <div class="variable" data-label="Note interne" data-type="text">Note interne</div>
      <div class="variable" data-label="Évaluation" data-type="enum">Évaluation</div>
    </div>
    <div class="constraint-info">
      <small>🔓 Accès à tous les champs usager + annotations précédentes seulement</small>
    </div>
  </div>
</div>
```

### Validation des contraintes d'ordre :

```ruby
# Validation côté serveur des références de formule
def validate_formula_references
  return unless formule?
  
  referenced_stable_ids = extract_stable_ids_from_expression(formule_expression)
  available_stable_ids = available_variables_for_formula(self).map { |v| v[:stable_id] }
  
  invalid_refs = referenced_stable_ids - available_stable_ids
  if invalid_refs.any?
    errors.add(:formule_expression, "Référence interdite à des champs non disponibles")
  end
end
```

### Évolutions futures possibles :

- **Intelligence artificielle** : génération de formules en langage naturel
- **Templates dynamiques** : création basée sur l'usage réel  
- **Validation avancée** : détection d'incohérences métier
- **Performance** : cache intelligent des calculs
- **Contraintes métier** : règles spécifiques par type de procédure