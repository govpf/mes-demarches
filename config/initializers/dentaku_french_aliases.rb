# frozen_string_literal: true

# pf: Alias FR des fonctions natives Dentaku.
#
# Avantage par rapport à `Calculator#add_function(name, type, lambda)` :
# l'inférence de type de l'AST suit la classe native (cf. SI/IF qui infère
# le type des branches dynamiquement). Notre ancienne approche `add_function`
# forçait un type unique (:numeric pour SI), ce qui faisait afficher "0.0"
# pour une formule SI qui retournait du texte.
#
# Limité aux fonctions sans question de "truthy semantics" : SI/IF utilise la
# sémantique Ruby (false/nil falsy seulement), ce qui colle. ET/OU/NON natifs
# (AND/OR/NOT) sont en revanche stricts (n'acceptent que des booléens, retournent
# nil sur 0/""), ce qui n'est pas le comportement attendu par un admin qui écrit
# `ET({CaseACocher}, ...)`. On les garde donc en lambdas custom dans
# FormulaCalculationService#add_french_functions, mais alignés sur Ruby pur
# (args.all? { |a| a }).
require 'dentaku'

# pf: CHERCHE et SUBSTITUE ne sont PAS aliasés ici parce que leur sémantique
# diffère du natif :
#   - CHERCHE : case-insensitive + 3e arg de position de départ + retourne 0
#     si non trouvé (FIND natif est case-sensitive, 2 args, retourne nil).
#   - SUBSTITUE : gsub (toutes occurrences). Substitute natif fait sub
#     (première occurrence seulement).
# Restent en lambda custom dans FormulaCalculationService#add_french_functions.
{
  SI:           :if,
  SOMME:        :sum,
  MOYENNE:      :avg,
  ABS:          :abs,
  ARRONDI:      :round,
  # pf: floor / ceil — ARRONDI_INF(-3.2) = -4, ARRONDI_SUP(-3.7) = -3.
  # Différent de ENTIER qui tronque vers zéro (ENTIER(-3.7) = -3).
  ARRONDI_INF:  :rounddown,
  ARRONDI_SUP:  :roundup,
  CONCATENER:   :concat,
  GAUCHE:       :left,
  DROITE:       :right,
  STXT:         :mid,
  NBCAR:        :len,
  # pf: étape H — agrégation / maths. count et sqrt sont natifs Dentaku 3.5.4.
  # NB / COMPTE comptent les éléments (utile sur un bloc : NB({Lignes})).
  NB:           :count,
  COMPTE:       :count,
  RACINE:       :sqrt,
  # pf: PLANCHER / PLAFOND = floor / ceil. Les natifs floor/ceil sont ABSENTS
  # en 3.5.4 ; on réutilise rounddown / roundup (déjà employés par
  # ARRONDI_INF / ARRONDI_SUP) — synonymes "math" pour la découvrabilité.
  PLANCHER:     :rounddown,
  PLAFOND:      :roundup,
}.each do |fr_name, native_name|
  native_class = Dentaku::AST::Function.get(native_name)
  Dentaku::AST::Function.register_class(fr_name, native_class)
end
