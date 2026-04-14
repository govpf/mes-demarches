# Spec : Bouton "Demander à mon IA"

## Contexte

Les administrateurs ne maîtrisent pas la syntaxe des formules. Mais ils ont accès à des assistants IA (ChatGPT, Claude, Gemini, etc.). L'idée est de leur fournir un prompt pré-rempli contenant la documentation syntaxique et la liste des champs du formulaire, qu'ils collent dans leur IA pour obtenir une formule prête à l'emploi.

## Fonctionnalité

Un bouton **"Demander à mon IA"** dans l'éditeur de formule qui copie dans le presse-papier un prompt structuré.

## Emplacement

Dans `app/components/types_de_champ_editor/champ_component/champ_component.html.haml`, à côté du textarea de l'expression de formule, sous le texte d'aide existant.

## Comportement

1. L'admin clique sur le bouton "Demander à mon IA" (icône clipboard ou robot)
2. Le contrôleur Stimulus collecte :
   - Les champs disponibles de la procédure (libellé + type) depuis les données déjà présentes dans l'éditeur
   - Le libellé du champ formule en cours d'édition
3. Un prompt est généré et copié dans le clipboard via `navigator.clipboard.writeText`
4. Un feedback visuel confirme la copie ("Copié !")
5. L'admin colle le prompt dans son IA, décrit ce qu'il veut, obtient la formule, la colle dans le textarea

## Structure du prompt généré

```
Je veux créer une formule pour le champ "{libellé du champ formule}" dans un formulaire administratif.

## Syntaxe des formules

### Références aux champs
Utilise la syntaxe {Nom du champ} pour référencer un champ.
Exemple : {Montant HT} * 1.20

### Fonctions disponibles

**Mathématiques** : SOMME(a, b, ...), MOYENNE(a, b, ...), MIN(a, b, ...), MAX(a, b, ...), ABS(x), ARRONDI(x, précision)
**Conditionnelles** : SI(condition, valeur_si_vrai, valeur_si_faux), ET(a, b, ...), OU(a, b, ...), NON(x)
**Texte** : CONCATENER(a, b, ...), GAUCHE(texte, n), DROITE(texte, n), STXT(texte, début, n), NBCAR(texte), CHERCHE(recherche, texte), SUBSTITUE(texte, ancien, nouveau), MAJUSCULE(texte), MINUSCULE(texte), SUPPRESPACE(texte)

### Opérateurs
Arithmétiques : +, -, *, /
Comparaison : =, !=, <, >, <=, >=

### Règles
- Une formule ne peut référencer que les champs qui la PRÉCÈDENT dans le formulaire
- Les champs Oui/Non valent 1 (oui) ou 0 (non) dans les calculs
- Les nombres décimaux utilisent le point comme séparateur

## Champs disponibles dans ce formulaire

{liste des champs avec type}

## Ma demande

[Décris ici ce que tu veux calculer]
```

## Implémentation technique

### Contrôleur Stimulus

Fichier : `app/javascript/controllers/formula_ia_prompt_controller.ts`

```typescript
import { Controller } from '@hotwired/stimulus'

export default class extends Controller {
  static targets = ['button']
  static values = {
    champLabel: String,
    availableChamps: Array // [{label: "Montant HT", type: "nombre entier"}, ...]
  }

  async copy() {
    const prompt = this.buildPrompt()
    await navigator.clipboard.writeText(prompt)
    // Feedback visuel
    this.buttonTarget.textContent = 'Copié !'
    setTimeout(() => { this.buttonTarget.textContent = 'Demander à mon IA' }, 2000)
  }

  buildPrompt(): string {
    // Construire le prompt avec la doc + les champs
  }
}
```

### Données côté serveur

Le `ChampComponent` passe les champs disponibles au contrôleur Stimulus via des `data-` attributes. Les champs sont déjà disponibles dans le contexte de l'éditeur (utilisés par l'autocomplétion).

### Mapping type_champ → libellé humain

```ruby
TYPE_LABELS_FR = {
  'text' => 'texte court',
  'textarea' => 'texte long',
  'integer_number' => 'nombre entier',
  'decimal_number' => 'nombre décimal',
  'date' => 'date',
  'yes_no' => 'oui/non',
  'drop_down_list' => 'liste déroulante',
  'checkbox' => 'case à cocher',
  # ...
}
```

## Critères d'acceptation

- [ ] Le bouton apparaît uniquement pour les champs de type formule
- [ ] Le prompt contient la documentation syntaxique complète (fonctions FR)
- [ ] Le prompt liste tous les champs précédant la formule avec leur type
- [ ] Le clipboard est rempli au clic
- [ ] Un feedback visuel confirme la copie
- [ ] Le bouton est accessible (aria-label, focus visible)
- [ ] Fonctionne sans connexion réseau (tout est côté client)

## Points ouverts

- Faut-il inclure les champs des blocs répétables dans le prompt ?
- Faut-il un textarea intégré "Décris ce que tu veux" pour que le prompt soit encore plus complet ?
- Faut-il proposer un lien direct vers ChatGPT/Claude avec le prompt pré-rempli (via URL) ?
