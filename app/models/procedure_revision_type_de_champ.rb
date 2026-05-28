# frozen_string_literal: true

class ProcedureRevisionTypeDeChamp < ApplicationRecord
  belongs_to :revision, class_name: 'ProcedureRevision'
  belongs_to :type_de_champ

  belongs_to :parent, class_name: 'ProcedureRevisionTypeDeChamp', optional: true
  # this relationship is necessary for cascade with dependent: :destroy
  has_many :children_revision_types_de_champ, -> { ordered }, foreign_key: :parent_id, class_name: 'ProcedureRevisionTypeDeChamp', inverse_of: :parent, dependent: :destroy
  has_one :procedure, through: :revision
  scope :root, -> { where(parent: nil) }
  scope :ordered, -> { order(:position, :id) }
  scope :revision_ordered, -> { order(:revision_id) }
  scope :public_only, -> { joins(:type_de_champ).where(types_de_champ: { private: false }) }
  scope :private_only, -> { joins(:type_de_champ).where(types_de_champ: { private: true }) }

  delegate :stable_id, :libelle, :description, :type_champ, :header_section?, :repetition?, :mandatory?, :public?, :private?, :to_typed_id, to: :type_de_champ
  delegate :type_de_champ, to: :parent, prefix: true, allow_nil: true

  default_scope { eager_load(:type_de_champ) }

  def revision_types_de_champ = revision.revision_types_de_champ.filter { _1.persisted? ? _1.parent_id == id : _1.parent == self }.sort_by(&:position)
  def types_de_champ = revision_types_de_champ.map(&:type_de_champ)

  def root?
    persisted? ? parent_id.nil? : parent.nil?
  end

  def child?
    parent_id.present?
  end

  def orphan?
    child? && !parent_type_de_champ.repetition?
  end

  def first?
    position == 0
  end

  def last?
    siblings.last == self
  end

  def empty?
    revision_types_de_champ.empty?
  end

  def siblings
    if child?
      parent.revision_types_de_champ
    elsif private?
      revision.revision_types_de_champ_private
    else
      revision.revision_types_de_champ_public
    end
  end

  def upper_coordinates
    upper = siblings.filter { |s| s.position < position }

    if child?
      upper += parent.upper_coordinates
    end

    if type_de_champ.private?
      upper += revision.revision_types_de_champ_public
    end

    upper
  end

  def siblings_starting_at(offset)
    siblings.filter { |s| (position + offset) <= s.position }
  end

  def previous_sibling
    index = siblings.index(self)
    if index > 0
      siblings[index - 1]
    end
  end

  def block
    if child?
      parent
    else
      revision
    end
  end

  def used_by_routing_rules?
    procedure.used_by_routing_rules?(type_de_champ)
  end

  def used_by_ineligibilite_rules?
    revision.ineligibilite_enabled? && stable_id.in?(revision.ineligibilite_rules&.sources || [])
  end

  def prefilled_by_type_de_champ
    revision.types_de_champ
      .filter(&:referentiel?)
      .find { stable_id.to_s.in?(it.referentiel_mapping_prefillable_stable_ids.map(&:to_s)) }
  end

  # pf: Formula-specific methods
  def in_repetition?
    # A formula is in a repetition if its parent is a repetition
    parent_type_de_champ&.repetition? || false
  end

  # pf: Building block — colonnes "hors bloc" pour une formule (parents +
  # system). Ne contient PAS les siblings : utilisée comme composant interne
  # par available_columns_for_formula (qui y ajoute les siblings) et par les
  # cas où on a besoin de distinguer parents vs siblings (collision warning,
  # available_in_repetition_context?). Hors bloc, équivalent à
  # available_columns_for_formula puisqu'il n'y a pas de notion de sibling.
  def available_parent_columns_for_formula
    return [] unless type_de_champ.formule?

    # System columns: always available
    system_columns = procedure.dossier_columns_for_export +
                     procedure.usager_columns_for_export

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

  # pf: Liste canonique des colonnes qu'une formule peut référencer (validation
  # backend ET autocomplete UI partagent cette liste — c'est la source de vérité).
  # Pour une formule dans un bloc répétable, inclut les siblings (champs antérieurs
  # de la même ligne) en plus des parents hors bloc.
  def available_columns_for_formula
    return [] unless type_de_champ.formule?

    parent_columns = available_parent_columns_for_formula

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

  def available_in_repetition_context?(column_ref)
    # For a formula in a repetition:
    # 1. Can reference fields from the same row (siblings) that precede it
    # 2. Can reference fields outside repetition (parents)

    # Fields from the same row (siblings in the repetition)
    sibling_columns = revision.children_of(parent_type_de_champ)
      .filter { |tdc| tdc.fillable? && revision.coordinate_for(tdc)&.position.to_i < position }
      .flat_map do |tdc|
        tdc.columns(procedure:).map { |col| type_de_champ.encode_column_id(col, tdc) }
      end

    # Parent fields (outside repetition)
    parent_columns = available_parent_columns_for_formula
      .filter { |col| col.is_a?(Columns::ChampColumn) }
      .map do |col|
        tdc = revision.types_de_champ.find { |t| col.stable_id == t.stable_id }
        tdc ? type_de_champ.encode_column_id(col, tdc) : nil
      end
      .compact

    (sibling_columns + parent_columns).include?(column_ref)
  end

  def check_collision_warning(column_ref, errors_collector)
    # Check if the field exists both in row AND parent
    # Extract stable_id from column_ref (e.g., "tdc456" -> 456)
    return unless column_ref.start_with?('tdc')

    stable_id = column_ref.match(/tdc(\d+)/)[1].to_i
    referenced_tdc = revision.types_de_champ.find { |t| t.stable_id == stable_id }
    return unless referenced_tdc

    # Get the libelle of the referenced field
    referenced_libelle = referenced_tdc.libelle

    # Check if a sibling field has this libelle
    sibling_tdcs = revision.children_of(parent_type_de_champ)
      .filter { |tdc| tdc.fillable? && revision.coordinate_for(tdc)&.position.to_i < position }

    has_sibling_with_libelle = sibling_tdcs.any? { |tdc| tdc.libelle == referenced_libelle }

    # Check if a parent field has this libelle
    parent_tdcs = available_parent_columns_for_formula
      .filter { |col| col.is_a?(Columns::ChampColumn) }
      .map { |col| revision.types_de_champ.find { |t| col.stable_id == t.stable_id } }
      .compact

    has_parent_with_libelle = parent_tdcs.any? { |tdc| tdc.libelle == referenced_libelle }

    # Collision detected: same libelle exists in both sibling and parent
    if has_sibling_with_libelle && has_parent_with_libelle
      # ⚠️ Warning only (not blocking error)
      errors_collector.add(:formule_expression,
        "⚠️ « #{referenced_libelle} » existe à la fois dans la ligne et comme champ parent. " \
        "La formule utilisera la valeur de la ligne (renommez l'un des deux pour plus de clarté).")
    end
  end
end
