# frozen_string_literal: true

# pf: Validator pour les formules - migré depuis TypeDeChamp#validate_formula_references
# pour résoudre le problème N+1 (136+ requêtes → <10 requêtes)
# Pattern identique à ConditionValidator : validation au niveau Procedure avec tous les tdcs préchargés
class TypesDeChamp::FormulaValidator < ActiveModel::EachValidator
  # Validate formula references across all formula fields
  # tdcs: all types_de_champ (public or private) already loaded
  # collection: :draft_types_de_champ_public or :draft_types_de_champ_private
  def validate_each(procedure, collection, tdcs)
    return if tdcs.empty?

    tdcs = tdcs_with_children(procedure, tdcs)
    revision = procedure.draft_revision

    # pf: Tous les tdcs sont déjà chargés par le preloader, pas de N+1
    tdcs.each_with_index do |tdc, tdc_index|
      next unless tdc.formule?
      next if tdc.formule_expression.blank?

      # Detect format: new (tdc456, dossier_number) or old (456, labels)
      has_new_format = tdc.formule_expression.match?(/\{(tdc\d+|dossier_|individual_|entreprise_)/)

      if has_new_format
        validate_column_references(procedure, collection, tdc, revision, tdcs, tdc_index)
      else
        validate_old_format_references(procedure, collection, tdc, revision, tdcs, tdc_index)
      end
    end
  end

  private

  # Find children in repetitions
  def tdcs_with_children(procedure, tdcs)
    tdcs.to_a
      .flat_map { _1.repetition? ? procedure.draft_revision.children_of(_1) : _1 }
  end

  # New validation using columns (format {tdc456}, {dossier_number}, etc.)
  def validate_column_references(procedure, collection, tdc, revision, all_tdcs, tdc_index)
    coordinate = revision.coordinate_for(tdc)
    return unless coordinate

    resolver = FormulaColumnResolver.new(revision, row_id: nil)

    # pf: Utilise TOUS les types_de_champ de la révision (pas juste la collection en cours)
    # car une annotation privée peut référencer des champs publics.
    all_revision_tdcs = revision.types_de_champ

    # Available columns with order constraints (from coordinate)
    available_column_ids = coordinate.available_columns_for_formula
      .filter { |col| col.is_a?(Columns::ChampColumn) }
      .map do |col|
        found_tdc = all_revision_tdcs.find { |t| col.stable_id == t.stable_id }
        found_tdc ? tdc.encode_column_id(col, found_tdc) : nil
      end
      .compact

    # Extract all references {tdc456}, {dossier_number}, {tdc456/commune}
    referenced_ids = tdc.formule_expression.scan(/\{([^}]+)\}/).map(&:first)

    # Validate each reference
    referenced_ids.each do |ref|
      column, _ = resolver.resolve_with_path(ref)

      if column.nil?
        add_error(procedure, collection, tdc, "Colonne inconnue : #{ref}")
        next
      end

      if column.champ_column?
        # Verify order constraints for champ columns
        base_ref = ref.split('/').first # tdc456

        if coordinate.in_repetition?
          # Formula IN repetition: can reference same-row fields + parent fields
          unless coordinate.available_in_repetition_context?(base_ref)
            add_error(procedure, collection, tdc, "ne peut référencer « #{column.label} » dans cette répétition")
            next
          end

          # ⚠️ Check for collision parent/row
          # Note: check_collision_warning ajoute directement à tdc.errors
          coordinate.check_collision_warning(base_ref, tdc.errors)
        else
          # Formula outside repetition: classic order constraints
          unless available_column_ids.include?(base_ref)
            add_error(procedure, collection, tdc, "ne peut référencer « #{column.label} » car une formule ne peut utiliser que les champs qui la précèdent")
          end
        end
      end
      # System columns (dossier_*, individual_*, etc.) are always accessible
    end
  end

  # Old validation for backward compatibility (format {Label} or {123})
  def validate_old_format_references(procedure, collection, tdc, revision, all_tdcs, tdc_index)
    # Available champs based on order constraints
    available_champs = available_champs_for_formula(tdc, revision, all_tdcs, tdc_index, collection == :draft_types_de_champ_private)
    available_stable_ids = available_champs.map(&:stable_id)

    # pf: Utilise all_tdcs déjà chargé au lieu de revision.types_de_champ (N+1)
    all_champs_for_resolution = all_tdcs

    # Build maps for label -> stable_id resolution
    label_to_stable_id = all_champs_for_resolution.each_with_object({}) do |t, hash|
      hash[t.libelle.strip.downcase] = t.stable_id
    end

    # Find all references (both labels and stable_ids)
    label_refs = tdc.formule_expression.scan(/\{([^\d}][^}]*)\}/).map(&:first)
    numeric_refs = tdc.formule_expression.scan(/\{(\d+)\}/).map { |match| match[0].to_i }

    # Resolve labels to stable_ids
    unknown_labels = []
    resolved_stable_ids = label_refs.map do |label|
      normalized_label = label.strip.downcase
      stable_id = label_to_stable_id[normalized_label]

      if stable_id.nil?
        unknown_labels << label
        nil
      else
        stable_id
      end
    end.compact

    # Combine resolved and direct stable_id references
    all_referenced_stable_ids = (resolved_stable_ids + numeric_refs).uniq

    # Check for truly unknown labels (not found in any champ)
    if unknown_labels.any?
      add_error(procedure, collection, tdc, "Champs inconnus : #{unknown_labels.join(', ')}")
      return
    end

    # Check for forbidden references (champs that exist but are not available due to order constraints)
    forbidden_refs = all_referenced_stable_ids - available_stable_ids
    if forbidden_refs.any?
      forbidden_labels = forbidden_refs.map do |stable_id|
        found_tdc = all_champs_for_resolution.find { |t| t.stable_id == stable_id }
        found_tdc&.libelle || "##{stable_id}"
      end.join(', ')

      if tdc.private?
        add_error(procedure, collection, tdc, "ne peut référencer « #{forbidden_labels} » car une annotation privée peut utiliser tous les champs publics et les annotations privées qui la précèdent")
      else
        add_error(procedure, collection, tdc, "ne peut référencer « #{forbidden_labels} » car une formule ne peut utiliser que les champs qui la précèdent")
      end
    end
  end

  # Determine available champs for a formula based on order constraints
  # Replaces TypeDeChamp#available_champs_for_formula to avoid N+1
  def available_champs_for_formula(tdc, revision, all_tdcs, tdc_index, is_private_collection)
    coordinate = revision.coordinate_for(tdc)
    return [] unless coordinate

    if tdc.private?
      # Private formulas can use all public champs + preceding private champs
      if is_private_collection
        # We have all private tdcs in order
        preceding_private = all_tdcs.take(tdc_index)
        public_tdcs = tdcs_with_children(revision.procedure, revision.procedure.draft_types_de_champ_public)
        public_tdcs + preceding_private
      else
        # Shouldn't happen, but fallback
        revision.types_de_champ_public + coordinate.upper_coordinates.filter(&:private?).map(&:type_de_champ)
      end
    else
      # Public formulas can only use preceding public champs
      if is_private_collection
        # Shouldn't happen (public tdc in private collection), but fallback
        coordinate.upper_coordinates.filter(&:public?).map(&:type_de_champ)
      else
        # We have all public tdcs in order
        all_tdcs.take(tdc_index)
      end
    end
  end

  # Add error to procedure with reference to the problematic type_de_champ
  def add_error(procedure, collection, tdc, message)
    # Format the error message with the TDC label
    full_message = "« #{tdc.libelle} » : #{message}"

    procedure.errors.add(
      collection,
      full_message,
      type_de_champ: tdc
    )
  end
end
