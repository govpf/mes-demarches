# frozen_string_literal: true

# pf: Service de génération d'une documentation textuelle à coller dans une
# IA externe (généraliste, au choix de l'administrateur) pour obtenir de l'aide
# à la rédaction d'une formule Dentaku.
#
# Le prompt agrège : un préambule pédagogique expliquant le workflow, le type
# de retour attendu, la liste exhaustive des variables référençables, la liste
# des variables existantes mais non accessibles (pour de meilleurs messages
# d'erreur), la whitelist des fonctions supportées, les règles de syntaxe, les
# limitations actuelles (dates, tableaux/blocs répétables), le format de réponse
# imposé (markdown avec bloc de code + explication courte) et une auto-
# vérification anti-hallucination.
class FormulaAiPromptService
  OUTPUT_TYPE_LABELS = {
    'string' => 'texte',
    'number' => 'nombre',
    'boolean' => 'booléen (true/false)'
  }.freeze

  # pf: Types de colonnes exposés par available_columns_for_formula_editor
  # traduits en libellés parlants pour une IA francophone.
  COLUMN_TYPE_LABELS = {
    text: 'texte',
    textarea: 'texte',
    email: 'texte',
    phone: 'texte',
    enum: 'texte (choix unique)',
    enums: 'texte (choix multiple)',
    integer_number: 'nombre entier',
    decimal_number: 'nombre décimal',
    boolean: 'booléen (true/false)',
    date: 'date',
    datetime: 'date et heure'
  }.freeze

  def initialize(type_de_champ:, coordinate:)
    @type_de_champ = type_de_champ
    @coordinate = coordinate
  end

  def generate
    sections = [
      header,
      preamble_section,
      output_type_section,
      variables_section,
      inaccessible_variables_section,
      functions_section,
      operators_and_syntax_section,
      unsupported_section,
      response_format_section,
      self_check_section,
      user_request_placeholder
    ].compact

    sections.join("\n\n").strip + "\n"
  end

  private

  attr_reader :type_de_champ, :coordinate

  def header
    <<~TXT
      === DOCUMENTATION POUR UNE IA : AIDE À LA RÉDACTION D’UNE FORMULE ===
    TXT
  end

  def preamble_section
    <<~TXT
      ## Préambule — comment fonctionne cette demande

      Tu reçois ce document parce qu’un administrateur de la plateforme
      **mes-demarches.pf** (démarches administratives dématérialisées en
      Polynésie française) a besoin d’écrire UNE formule Dentaku pour UN
      champ précis de son formulaire.

      L’administrateur **n’est pas forcément développeur**. Il ne connaît
      pas la syntaxe exacte de Dentaku ni la liste des variables disponibles
      dans son formulaire. C’est pour cela que ce document t’est fourni :
      il contient **tout le contexte nécessaire** à cette formule spécifique
      (type de retour, variables référençables, fonctions supportées,
      limitations, format de réponse).

      ⚠️ **Ce document concerne UN SEUL champ formule.** Si tu as déjà aidé
      à rédiger une formule dans cette conversation, le contexte précédent
      ne s’applique PAS ici : les variables et fonctions disponibles peuvent
      différer d’un champ à l’autre. **Repars de zéro** avec ce document.

      Ta mission :
      1. Lire ce document intégralement.
      2. Lire le besoin exprimé par l’administrateur en bas du document.
      3. Répondre au format précisé plus bas : **la formule dans un bloc de code**,
         suivie d’une **courte explication** pour que l’administrateur
         comprenne ce qu’elle fait.
    TXT
  end

  def output_type_section
    type_label = OUTPUT_TYPE_LABELS[type_de_champ.formule_output_type.to_s] || 'non défini (inféré de la formule)'

    <<~TXT
      ## Type de résultat attendu

      La formule doit retourner un **#{type_label}**.
    TXT
  end

  def variables_section
    columns = available_columns
    if columns.empty?
      return <<~TXT
        ## Variables disponibles

        Aucune variable n’est actuellement référençable depuis cette formule.
      TXT
    end

    lines = columns.map do |col|
      type_label = COLUMN_TYPE_LABELS[col.type.to_sym] || col.type.to_s
      "- `{#{col.label}}` — #{type_label}"
    end

    context_note = in_repetition? ? repetition_context_note : ''

    <<~TXT
      ## Variables disponibles

      Les variables se référencent par leur libellé exact entre accolades : `{Libellé du champ}`.

      Liste **exhaustive** des variables disponibles pour cette formule :

      #{lines.join("\n")}

      ⚠️ Si tu veux référencer un champ qui n’est PAS dans cette liste, NE L’INVENTE PAS.#{context_note}
    TXT
  end

  def inaccessible_variables_section
    tdcs = inaccessible_fillable_tdcs
    return nil if tdcs.empty?

    lines = tdcs.map do |tdc|
      type_label = human_type_label_for_tdc(tdc)
      "- `{#{tdc.libelle}}` — #{type_label}"
    end

    <<~TXT
      ## Variables présentes dans le formulaire mais NON accessibles

      Pour information, les champs suivants existent dans la démarche mais
      **ne sont PAS référençables** depuis cette formule. Le plus souvent,
      c’est parce qu’ils sont placés **après** cette formule dans le
      formulaire (seuls les champs qui précèdent sont utilisables) ou parce
      qu’ils se trouvent dans un autre contexte (bloc répétable différent,
      annotation privée, etc.).

      #{lines.join("\n")}

      Si le besoin nécessite l’un de ces champs, réponds `IMPOSSIBLE` en
      précisant lequel et pourquoi — l’administrateur pourra alors
      réorganiser son formulaire.
    TXT
  end

  def functions_section
    <<~TXT
      ## Fonctions autorisées (liste exhaustive)

      ### Arithmétique
      - `SOMME(a, b, ...)` → nombre — somme de tous les arguments
      - `MOYENNE(a, b, ...)` → nombre — moyenne arithmétique
      - `MIN(a, b, ...)` / `MAX(a, b, ...)` → nombre
      - `ABS(n)` → nombre — valeur absolue
      - `ARRONDI(n, [décimales])` → nombre — arrondi à `décimales` chiffres (0 par défaut)

      ### Logique
      - `SI(condition, valeur_si_vrai, valeur_si_faux)` — équivalent ternaire
      - `ET(a, b, ...)` → booléen
      - `OU(a, b, ...)` → booléen
      - `NON(a)` → booléen

      ### Texte
      - `CONCATENER(a, b, ...)` → texte — concatène tous les arguments
      - `GAUCHE(texte, n)` → texte — n premiers caractères
      - `DROITE(texte, n)` → texte — n derniers caractères
      - `STXT(texte, position, n)` → texte — sous-chaîne (position commence à 1)
      - `NBCAR(texte)` → nombre — nombre de caractères
      - `CHERCHE(motif, texte, [position])` → nombre — position (1-indexée, 0 si absent, non sensible à la casse)
      - `SUBSTITUE(texte, ancien, nouveau)` → texte — remplace toutes les occurrences
      - `MAJUSCULE(texte)` / `MINUSCULE(texte)` → texte
      - `SUPPRESPACE(texte)` → texte — supprime les espaces en début/fin et réduit les espaces multiples
      - `VALEUR(texte)` → nombre — convertit un texte en nombre (gère la virgule française, retourne 0 si non convertible)

      ### Date
      Les champs de type date sont manipulés comme des objets Date natifs. L’arithmétique `+` `-` et les comparaisons `<` `>` `==` fonctionnent directement entre deux dates, ou entre une date et une durée.

      - `AUJOURDHUI()` → date — la date du jour
      - `MAINTENANT()` → date et heure — l’instant courant
      - `JOUR(date)` → nombre — jour du mois (1 à 31)
      - `MOIS(date)` → nombre — mois (1 à 12)
      - `ANNEE(date)` → nombre — année sur 4 chiffres
      - `JOURSEM(date)` → nombre — jour de la semaine ISO (lundi = 1, ..., dimanche = 7)
      - `AGE(date_de_naissance)` → nombre — âge en années révolues (tient compte de l’anniversaire)
      - `EST_PASSEE(date)` → booléen — la date est-elle strictement antérieure à aujourd’hui ?
      - `EST_FUTURE(date)` → booléen — la date est-elle strictement postérieure à aujourd’hui ?
      - `DUREE_ANNEES(n)` / `DUREE_MOIS(n)` / `DUREE_JOURS(n)` → durée — à utiliser en arithmétique avec une date. Ex : `{DateNaissance} + DUREE_ANNEES(18)` → date du 18e anniversaire.
      - `DURATION(n, years|months|days)` → durée — équivalent anglais natif, interchangeable avec les `DUREE_*`.

      Opérations dérivées de l’arithmétique native :
      - `{Date1} - {Date2}` → nombre de jours entre deux dates (entier si les deux sont des dates simples).
      - `{Date} + DUREE_JOURS(n)` / `{Date} - DUREE_MOIS(n)` → nouvelle date.
      - `{Date} < AUJOURDHUI()` équivaut à `EST_PASSEE({Date})`.
    TXT
  end

  def operators_and_syntax_section
    <<~TXT
      ## Opérateurs et syntaxe

      ### Opérateurs
      - Arithmétiques : `+`  `-`  `*`  `/`  `%` (modulo)  `^` (puissance)
      - Comparaison : `==`  `!=`  `<`  `<=`  `>`  `>=`
      - Logiques : utilise les fonctions `ET()`, `OU()`, `NON()` (les mots-clés AND/OR/NOT fonctionnent aussi mais préfère les fonctions FR)

      ### Règles de syntaxe
      1. **Références aux champs** : toujours avec accolades `{...}`, jamais `$` ni `%`. Le libellé doit correspondre EXACTEMENT à un libellé de la liste des variables.
      2. **Égalité** : utilise `==` et PAS `=` seul. `=` seul produit une erreur de syntaxe.
      3. **Chaînes de caractères** : entre guillemets doubles `"texte"`.
      4. **Booléens** : `true` / `false` (tout en minuscules).
      5. **Pas de variables intermédiaires, pas de boucles, pas d’assignation.** Une formule est une expression unique.
    TXT
  end

  def unsupported_section
    <<~TXT
      ## Fonctionnalités NON DISPONIBLES actuellement

      ### Blocs répétables (tableaux)
      Un « bloc répétable » est un groupe de champs que l’usager peut dupliquer
      (par exemple : liste d’enfants, liste de revenus, liste de dépenses).
      On peut se les représenter comme un **tableau** :
      - une **colonne** par champ du bloc (ex: « Prénom de l’enfant », « Âge de l’enfant »),
      - une **ligne** par répétition remplie par l’usager.

      ⚠️ **Aucune fonction ne peut actuellement manipuler ces tableaux.** Il est impossible de :
      - compter le nombre de lignes (pas de NBLIGNES, NB.SI, ...),
      - sommer une colonne sur toutes les lignes (pas de SOMME.SI, SOMMEPROD, ...),
      - filtrer les lignes selon une condition,
      - accéder à une ligne précise par son index.

      Les champs situés DANS un bloc répétable ne sont référençables depuis une
      formule située elle aussi DANS le même bloc (la formule est alors
      évaluée ligne par ligne). **Aucun agrégat global n’est possible.**

      **Si le besoin implique un agrégat sur un bloc répétable** (total, moyenne,
      nombre de lignes, ...), réponds `IMPOSSIBLE`.
    TXT
  end

  def response_format_section
    <<~TXT
      ## Format de réponse attendu

      Réponds en **DEUX parties** :

      **1. La formule, dans un bloc de code Markdown** (triple backticks) pour
      que l’administrateur puisse la copier en un clic. Exemple :

      ```
      SI({Âge} >= 18, "Majeur", "Mineur")
      ```

      **2. Une courte explication** (2 à 4 phrases maximum) du fonctionnement
      de la formule : ce qu’elle calcule, les cas qu’elle traite, et
      éventuellement une limite à connaître. L’administrateur doit pouvoir
      valider que la formule correspond à son besoin sans avoir à lire la
      syntaxe Dentaku.

      ---

      **Si le besoin ne peut PAS être satisfait** avec les fonctions et
      variables disponibles :

      - **N’utilise PAS de bloc de code** (il n’y a pas de formule valide).
      - Commence ta réponse par une ligne `IMPOSSIBLE: <raison courte>`.
      - Ajoute si possible une **suggestion** concrète (reformuler le besoin,
        réorganiser le formulaire, faire saisir autrement…).

      Exemples de réponses IMPOSSIBLE valides :
      - `IMPOSSIBLE: aucune agrégation sur un bloc répétable n’est disponible.` Suggestion : faire saisir un total directement par l’usager dans un champ nombre, ou ajouter un champ formule dans le bloc qui sera ensuite exploité hors bloc une fois la Phase 2 du moteur déployée.
      - `IMPOSSIBLE: le champ « Nom du conjoint » existe mais n’est pas accessible depuis cette formule.` Suggestion : placer « Nom du conjoint » avant le champ formule dans le formulaire.
    TXT
  end

  def self_check_section
    <<~TXT
      ## Auto-vérification avant d’envoyer ta réponse

      1. ✅ Si tu donnes une formule, elle est dans un bloc de code Markdown (triple backticks) ?
      2. ✅ Chaque fonction utilisée figure bien dans la liste « Fonctions autorisées » ?
      3. ✅ Chaque variable `{...}` figure bien dans « Variables disponibles » (et PAS dans « Variables NON accessibles ») ?
      4. ✅ Le type de retour correspond au type attendu ?
      5. ✅ Tu n’utilises pas `=` seul pour tester une égalité ?
      6. ✅ Tu n’utilises aucune fonction d’agrégation sur un bloc répétable (non supportée) ?
      7. ✅ Ton explication tient en 2 à 4 phrases et est compréhensible par un non-développeur ?

      Si une seule de ces vérifications échoue, **reformule ou réponds IMPOSSIBLE**.
    TXT
  end

  def user_request_placeholder
    <<~TXT
      ## Ce que je veux calculer

      [DÉCRIS ICI EN FRANÇAIS CE QUE LA FORMULE DOIT CALCULER]
    TXT
  end

  def repetition_context_note
    "\n\nNote : ce champ formule est situé à l’intérieur d’un bloc répétable. Il sera évalué ligne par ligne, avec les valeurs de la ligne courante."
  end

  def available_columns
    @available_columns ||= coordinate.available_columns_for_formula_editor.filter do |col|
      col.label.present? && col.type.present?
    end
  end

  # pf: TDC fillable de la démarche qui n'apparaissent PAS dans les variables
  # disponibles. Utile pour que l'IA puisse diagnostiquer un besoin non
  # satisfiable parce qu'un champ existe mais n'est pas accessible (ordre,
  # bloc répétable, annotation privée).
  def inaccessible_fillable_tdcs
    @inaccessible_fillable_tdcs ||= begin
      accessible_stable_ids = available_columns
        .filter_map { |col| col.respond_to?(:stable_id) ? col.stable_id : nil }
        .to_set

      coordinate.revision.types_de_champ.filter do |tdc|
        tdc.fillable? &&
          tdc.stable_id != type_de_champ.stable_id &&
          !accessible_stable_ids.include?(tdc.stable_id)
      end
    end
  end

  def human_type_label_for_tdc(tdc)
    key = tdc.type_champ.to_s
    case key
    when 'text', 'textarea', 'email', 'phone', 'formatted', 'civilite'
      'texte'
    when 'integer_number'
      'nombre entier'
    when 'decimal_number', 'number'
      'nombre décimal'
    when 'yes_no', 'checkbox'
      'booléen (true/false)'
    when 'date'
      'date'
    when 'datetime'
      'date et heure'
    when 'drop_down_list', 'multiple_drop_down_list', 'linked_drop_down_list'
      'liste de choix'
    when 'repetition'
      'bloc répétable (tableau)'
    when 'piece_justificative', 'titre_identite'
      'pièce jointe'
    when 'formule'
      'formule'
    else
      key
    end
  end

  def in_repetition?
    coordinate.child?
  end
end
