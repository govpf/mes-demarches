# frozen_string_literal: true

# Service to resolve formula column references to actual Column objects
# Converts semantic identifiers like "tdc456" or "dossier_number" to Column instances
class FormulaColumnResolver
  def initialize(revision, row_id: nil)
    @revision = revision
    @procedure = revision.procedure
    @row_id = row_id # Context: row_id of the formula itself (nil if outside repetition)
    @columns_by_id = build_columns_index
  end

  # Resolves {tdc456} or {dossier_number} → Column
  def resolve(column_id)
    @columns_by_id[column_id]
  end

  # Resolves {tdc456/date_de_naissance} → [Column, path]
  #
  # pf: Les colonnes à sous-chemin (JSONPathColumn, LinkedDropDownColumn) sont
  # indexées sous leur clé COMPLÈTE "tdc<N>/<path>" par encode_column_id. On
  # consulte donc d'abord la clé complète : la colonne trouvée porte déjà sa
  # propre logique d'extraction (jsonpath / path), on renvoie path=nil.
  # Avant ce correctif, resolve_with_path splittait systématiquement et ne
  # résolvait que le préfixe "tdc<N>" → la ChampColumn de base, jamais la
  # JSONPathColumn — donc {Numéro DN/date_de_naissance}, {SIRET/raison_sociale}
  # etc. retournaient nil en formule. Le fallback split conserve l'ancien
  # comportement pour toute clé composite non indexée.
  def resolve_with_path(reference)
    if reference.include?('/')
      full_column = @columns_by_id[reference]
      return [full_column, nil] if full_column

      column_id, path = reference.split('/', 2)
      [resolve(column_id), path.to_sym]
    else
      [resolve(reference), :value]
    end
  end

  private

  def build_columns_index
    index = {}

    # System columns (dossier, user, etc.) - using semantic tag names
    build_system_columns_index(index)

    # Type de champ columns (tdc<N>)
    @revision.types_de_champ.each do |tdc|
      tdc.columns(procedure: @procedure).each do |col|
        # Encode according to attestation v2 pattern
        id = encode_column_id(col, tdc)
        index[id] = col
      end
    end

    index
  end

  def build_system_columns_index(index)
    # Map dossier columns using semantic tags from TagsSubstitutionConcern
    # For now, we'll map the most common ones manually
    # TODO: Generate this automatically from TagsSubstitutionConcern

    # Dossier metadata
    index['dossier_number'] = find_column_by_table_and_column('self', 'id')
    index['dossier_state'] = find_column_by_table_and_column('self', 'state')
    index['dossier_depose_at'] = find_column_by_table_and_column('self', 'depose_at')
    index['dossier_en_instruction_at'] = find_column_by_table_and_column('self', 'en_instruction_at')
    index['dossier_processed_at'] = find_column_by_table_and_column('self', 'processed_at')

    # Individual columns (if procedure is for individual)
    if @procedure.for_individual
      index['individual_gender'] = find_column_by_table_and_column('individual', 'gender')
      index['individual_first_name'] = find_column_by_table_and_column('individual', 'prenom')
      index['individual_last_name'] = find_column_by_table_and_column('individual', 'nom')
    end

    # Entreprise columns (if procedure is for moral person)
    unless @procedure.for_individual
      index['entreprise_siren'] = find_column_by_table_and_column('etablissement', 'entreprise_siren')
      index['entreprise_siret'] = find_column_by_table_and_column('etablissement', 'siret')
      index['entreprise_raison_sociale'] = find_column_by_table_and_column('etablissement', 'entreprise_raison_sociale')
    end

    # Remove nil values (columns that don't exist)
    index.compact!
  end

  def find_column_by_table_and_column(table, column)
    @procedure.columns.find { |col| col.table == table && col.column.to_s == column.to_s }
  end

  def encode_column_id(column, tdc)
    if column.is_a?(Columns::ChampColumn) && !column.is_a?(Columns::JSONPathColumn) && !column.is_a?(Columns::LinkedDropDownColumn)
      # Basic champ column
      "tdc#{tdc.stable_id}"
    elsif column.is_a?(Columns::JSONPathColumn)
      # JSON path column (DN date_de_naissance, code postal communes, etc.)
      path_name = extract_path_name(column.jsonpath)
      "tdc#{tdc.stable_id}/#{path_name}"
    elsif column.is_a?(Columns::LinkedDropDownColumn)
      # Linked drop down (primary/secondary values)
      "tdc#{tdc.stable_id}/#{column.path}"
    else
      # Fallback: use column_id
      # This shouldn't happen for type_de_champ columns
      column.send(:column_id)
    end
  end

  def extract_path_name(jsonpath)
    # jsonpath format: "$.path.to.value"
    # We want the last segment: "value"
    parts = jsonpath.split('.')
    parts.last
  end
end
