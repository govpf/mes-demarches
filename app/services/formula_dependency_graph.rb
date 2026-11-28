# frozen_string_literal: true

# pf: graphe de dépendances des formules d'une révision. Construit en une
# seule lecture de revision.revision_types_de_champ, sans état modifiable.
#
# - Nœuds : chaque formule, avec son niveau (:public, :private, ou :row pour
#   une formule-ligne d'un bloc répétable, avec le stable_id du bloc).
# - Arêtes : lues dans l'expression (FormulaReferences) — :champ ({tdcN},
#   {tdcN/chemin}), :bloc ({tdcBloc}) ou :sub_champ ({tdcBloc/sub_M}).
# - Ordre de calcul : public dans l'ordre des positions, chaque bloc déplié à
#   sa place, puis privé selon la même logique.
# - Drapeaux (has_clock, has_state, has_identite) : lus dans formule_deps.
class FormulaDependencyGraph
  Node = Data.define(:stable_id, :type_de_champ, :level, :bloc_stable_id)
  Edge = Data.define(:kind, :stable_id, :sub_stable_id)

  def initialize(revision)
    coordinates = revision.revision_types_de_champ.to_a
    children_by_parent_id = coordinates.filter(&:child?).group_by(&:parent_id)
    coordinates_by_id = coordinates.index_by(&:id)
    @coordinates = coordinates.index_by(&:stable_id).freeze
    @bloc_stable_ids = coordinates.filter(&:repetition?).to_set(&:stable_id).freeze
    @parent_stable_ids = coordinates.filter(&:child?).to_h do |coordinate|
      [coordinate.stable_id, coordinates_by_id[coordinate.parent_id]&.stable_id]
    end.freeze

    ordered = (revision.revision_types_de_champ_public + revision.revision_types_de_champ_private)
      .flat_map { |root| [root, *children_by_parent_id.fetch(root.id, []).sort_by(&:position)] }

    @nodes = ordered.filter { _1.type_de_champ.formule? }.to_h do |coordinate|
      [coordinate.stable_id, build_node(coordinate)]
    end.freeze
    @edges = @nodes.transform_values { edges_for(_1.type_de_champ.formule_expression) }.freeze
    @dependents = Hash.new { [] }
    @edges.each do |formula_stable_id, edges|
      edges.map(&:stable_id).uniq.each { @dependents[_1] += [formula_stable_id] }
    end
    @dependents.freeze
  end

  def any_formula? = @nodes.any?

  def node(stable_id) = @nodes[stable_id]

  def formula_stable_ids = @nodes.keys

  def formula_types_de_champ(only: nil)
    only = only&.to_set
    @nodes.values.filter_map { _1.type_de_champ if only.nil? || only.include?(_1.stable_id) }
  end

  def edges(stable_id) = @edges.fetch(stable_id, [])

  # Formules à recalculer quand les sources changent, dans l'ordre de calcul.
  # Un sous-champ fait suivre son bloc parent (les agrégats dépendent du bloc),
  # et une formule-ligne atteinte fait de même.
  def downstream_of(source_stable_ids)
    to_follow = source_stable_ids.flat_map { [_1, @parent_stable_ids[_1]] }.compact.uniq
    followed = to_follow.to_set
    reached = Set.new

    while (source = to_follow.shift)
      @dependents[source].each do |formula_stable_id|
        reached << formula_stable_id
        bloc_stable_id = @nodes[formula_stable_id].bloc_stable_id
        [formula_stable_id, bloc_stable_id].compact.each do |next_source|
          to_follow << next_source if followed.add?(next_source)
        end
      end
    end

    in_order(reached)
  end

  def flagged(flag, private_only: false)
    @nodes.values.filter_map do |node|
      tdc = node.type_de_champ
      node.stable_id if tdc.formule_deps&.[](flag) && (!private_only || tdc.private?)
    end
  end

  # Avec private_only, le résultat est refiltré sur les formules privées : le
  # périmètre ne dépend pas de la règle de visibilité (une formule publique
  # ne lit pas une formule privée).
  def flagged_with_downstream(flag, private_only: false)
    flagged = flagged(flag, private_only:)
    result = in_order(flagged.to_set + downstream_of(flagged))
    private_only ? result.filter { @nodes[_1].type_de_champ.private? } : result
  end

  # Vrai si `expression`, placée sur la formule `stable_id`, la fait dépendre
  # d'elle-même (directement ou par d'autres formules enregistrées).
  def circular_reference?(stable_id, expression)
    return false if stable_id.nil?

    to_visit = targets(edges_for(expression))
    visited = Set.new
    while (target = to_visit.shift)
      return true if target == stable_id
      next unless visited.add?(target)

      to_visit.concat(targets(edges(target)))
    end
    false
  end

  # Vrai si `expression` référence un champ hors de ce que la règle de
  # visibilité (FormulaReferenceScope) autorise pour la formule `stable_id`.
  def forward_reference?(stable_id, expression)
    coordinate = stable_id && @coordinates[stable_id]
    return false if coordinate.nil?

    allowed = FormulaReferenceScope.new(coordinate).allowed_stable_ids
    FormulaReferences.scan(expression).any? { _1.champ? && !allowed.include?(_1.stable_id) }
  end

  private

  def build_node(coordinate)
    level = if coordinate.child?
      :row
    else
      coordinate.public? ? :public : :private
    end
    bloc_stable_id = @parent_stable_ids[coordinate.stable_id] if coordinate.child?
    Node.new(stable_id: coordinate.stable_id, type_de_champ: coordinate.type_de_champ, level:, bloc_stable_id:)
  end

  def edges_for(expression)
    FormulaReferences.scan(expression).filter(&:champ?).map do |ref|
      kind = if ref.sub_champ?
        :sub_champ
      elsif ref.path.nil? && @bloc_stable_ids.include?(ref.stable_id)
        :bloc
      else
        :champ
      end
      Edge.new(kind:, stable_id: ref.stable_id, sub_stable_id: ref.sub_stable_id)
    end.uniq.freeze
  end

  # Pour :bloc et :sub_champ, la cible est le bloc (non formule, donc terminal).
  def targets(edges) = edges.map(&:stable_id)

  def in_order(stable_ids) = @nodes.keys.filter { stable_ids.include?(_1) }
end
