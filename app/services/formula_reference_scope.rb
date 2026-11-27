# frozen_string_literal: true

# pf: règle de visibilité des références d'une formule — quelles colonnes et
# quels blocs répétables une formule a le droit de référencer, selon sa
# coordonnée dans la révision. Déménagée depuis ProcedureRevisionTypeDeChamp.
class FormulaReferenceScope
  def initialize(coordinate)
    @coordinate = coordinate
  end

  # Building block — colonnes "hors bloc" pour une formule (parents + system).
  # Ne contient PAS les siblings : composant interne de #columns (qui y ajoute
  # les siblings) et des cas où il faut distinguer parents vs siblings
  # (collision warning, available_in_repetition_context?). Hors bloc,
  # équivalent à #columns puisqu'il n'y a pas de notion de sibling.
  def parent_columns
    return [] unless type_de_champ.formule?

    # System columns: always available
    # pf: restreintes à la liste blanche de FormulaSystemColumns (seules
    # colonnes que le resolver sait résoudre et que le calcul garde à jour).
    system_columns = (procedure.dossier_columns_for_export + procedure.usager_columns_for_export)
      .filter { FormulaSystemColumns.formula_id(_1) }

    # pf: ordre de retour — TDC champs d'ABORD, colonnes système ensuite.
    # L'autocomplete frontend ne montre par défaut que les ~10 premières
    # colonnes (slice + fuzzy match limité). Les ~46 colonnes système qui
    # étaient en tête masquaient totalement les TDC champs dans le dropdown
    # d'une annotation privée formule (volume des system_columns >> 10).
    # Mettre les TDC en premier reflète aussi la fréquence d'usage : 99%
    # des formules référencent un champ du formulaire, pas un état système.
    if in_repetition?
      # All fields that precede the parent repetition
      parent_position = parent.position

      if private?
        # Private annotation in repetition: all public + private before the repetition
        public_columns = revision.types_de_champ_public
          .filter(&:fillable?)
          .flat_map { |tdc| tdc.columns(procedure:) }

        private_columns = revision.types_de_champ_private
          .filter { |tdc| tdc.fillable? && revision.coordinate_for(tdc)&.position.to_i < parent_position }
          .flat_map { |tdc| tdc.columns(procedure:) }

        public_columns + private_columns + system_columns
      else
        # Public field in repetition: public fields before the repetition
        champ_columns = revision.types_de_champ_public
          .filter { |tdc| tdc.fillable? && revision.coordinate_for(tdc)&.position.to_i < parent_position }
          .flat_map { |tdc| tdc.columns(procedure:) }

        champ_columns + system_columns
      end
    else
      # Formula outside repetition: classic order constraints
      if private?
        # Annotation: all public + preceding private
        public_columns = revision.types_de_champ_public
          .filter(&:fillable?)
          .flat_map { |tdc| tdc.columns(procedure:) }

        private_columns = revision.types_de_champ_private
          .filter { |tdc| tdc.fillable? && revision.coordinate_for(tdc)&.position.to_i < position }
          .flat_map { |tdc| tdc.columns(procedure:) }

        public_columns + private_columns + system_columns
      else
        # Public field: preceding public fields only
        champ_columns = revision.types_de_champ_public
          .filter { |tdc| tdc.fillable? && revision.coordinate_for(tdc)&.position.to_i < position }
          .flat_map { |tdc| tdc.columns(procedure:) }

        champ_columns + system_columns
      end
    end
  end

  # Liste canonique des colonnes qu'une formule peut référencer (validation
  # backend ET autocomplete UI partagent cette liste — c'est la source de vérité).
  # Pour une formule dans un bloc répétable, inclut les siblings (champs antérieurs
  # de la même ligne) en plus des parents hors bloc.
  def columns
    return [] unless type_de_champ.formule?

    parent_columns = self.parent_columns

    # pf: les siblings (champs de la même row) sont les plus pertinents pour
    # une formule en répétition — ils précèdent même les parents. Mis en
    # tête de liste pour qu'ils apparaissent dès l'ouverture du dropdown
    # d'autocomplete (cf. slice frontend).
    if in_repetition?
      sibling_columns = revision.children_of(parent_type_de_champ)
        .filter { |tdc| tdc.fillable? && revision.coordinate_for(tdc)&.position.to_i < position }
        .flat_map { |tdc| tdc.columns(procedure:) }

      sibling_columns + parent_columns
    else
      parent_columns
    end
  end

  # Blocs répétables qu'une formule peut agréger (NB({Bloc}), SOMME({Bloc/Sous-champ})) :
  # ceux qui la précèdent (ou précèdent son bloc parent), plus tous les blocs publics
  # pour une annotation privée. Les positions publiques et privées étant numérotées
  # séparément, on passe par upper_coordinates au lieu de comparer des positions.
  # Source de vérité partagée par l'éditeur, FormulaValidator et forward_reference?.
  def aggregable_repetitions
    upper_coordinates
      .map(&:type_de_champ)
      .filter(&:repetition?)
      .uniq(&:stable_id)
  end

  # stable_id des champs référençables : colonnes de champ + blocs agrégables.
  def allowed_stable_ids
    column_ids = columns.filter_map { _1.stable_id if _1.is_a?(Columns::ChampColumn) }
    Set.new(column_ids + aggregable_repetitions.map(&:stable_id))
  end

  private

  delegate :revision, :procedure, :position, :parent, :private?, :in_repetition?,
    :parent_type_de_champ, :upper_coordinates, :type_de_champ, to: :@coordinate
end
