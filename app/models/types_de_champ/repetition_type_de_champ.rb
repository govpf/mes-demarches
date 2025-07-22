# frozen_string_literal: true

class TypesDeChamp::RepetitionTypeDeChamp < TypesDeChamp::TypeDeChampBase
  include ActionView::Helpers::TagHelper

  def champ_value_for_tag(champ, path = :value)
    return nil if path != :value
    rows = champ.rows
    return champ_default_value if rows.blank?

    # pf displays repetition as table
    header = tag.tr(rows[0].map { |c| tag.th(c.libelle) }.reduce(&:+))
    lines = rows.map do |champs|
      tag.tr(champs.map do |champ|
        tag.td(champ.type_de_champ.champ_value_for_tag(champ))
      end.reduce(&:+))
    end.reduce(&:+)
    tag.table(header + lines)
  end

  def estimated_fill_duration(revision)
    estimated_rows_in_repetition = 2.5

    children = revision.children_of(@type_de_champ)

    estimated_row_duration = children.map { _1.estimated_fill_duration(revision) }.sum
    estimated_children_read_duration = children.map(&:estimated_read_duration).sum

    # Count only once children read time for all rows
    estimated_row_duration * estimated_rows_in_repetition + estimated_children_read_duration
  end

  # We have to truncate the label here as spreadsheets have a (30 char) limit on length.
  def libelle_for_export
    str = "(#{stable_id}) #{libelle}"
    # /\*?[] are invalid Excel worksheet characters
    ActiveStorage::Filename.new(str.delete('[]*?')).sanitized
  end

  def columns(procedure_id:, displayable: true, prefix: nil)
    @type_de_champ.procedure
      .all_revisions_types_de_champ(parent: @type_de_champ)
      .flat_map { _1.columns(procedure_id:, displayable: false, prefix: libelle) }
  end
end
