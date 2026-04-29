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
  SI:         :if,
  SOMME:      :sum,
  MOYENNE:    :avg,
  ABS:        :abs,
  ARRONDI:    :round,
  CONCATENER: :concat,
  GAUCHE:     :left,
  DROITE:     :right,
  STXT:       :mid,
  NBCAR:      :len
}.each do |fr_name, native_name|
  native_class = Dentaku::AST::Function.get(native_name)
  Dentaku::AST::Function.register_class(fr_name, native_class)
end
