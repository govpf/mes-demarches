# frozen_string_literal: true

class TypesDeChamp::PieceJustificativeTypeDeChamp < TypesDeChamp::TypeDeChampBase
  include ActionView::Helpers::TagHelper

  def estimated_fill_duration(revision)
    FILL_DURATION_LONG
  end

  # pf allows referencing PJs
  # def tags_for_template = [].freeze

  def champ_value_for_tag(champ, path = nil)
    return nil unless champ.piece_justificative_file.attached?

    champ.piece_justificative_file.each_with_index.filter_map do |attachment, i|
      if attachment.virus_scanner.safe? || attachment.virus_scanner.pending?
        url = download_url(champ, i)
        display = attachment.filename
        if attachment.image?
          tag.img '', src: url, width: '100', id: attachment.id, display: display
        else
          tag.a(display, href: url, target: '_blank', rel: 'noopener', title: "Télécharger la pièce jointe")
        end
      end
    end.flat_map { |e| [e, ",", tag.br] }[0..-3].reduce(&:+)
  end

  def download_url(champ, index)
    Rails.application.routes.url_helpers.champs_piece_justificative_download_url(
      { dossier_id: champ.dossier_id, stable_id: champ.stable_id, h: champ.encoded_date(:created_at), i: index, row_id: champ.row_id }
    )
  end

  def champ_value_for_export(champ, path = :value)
    champ.piece_justificative_file.map { _1.filename.to_s }.join(', ')
  end

  def champ_value_for_api(champ, version: 2)
    return if version == 2

    # API v1 don't support multiple PJ
    attachment = champ.piece_justificative_file.first
    return if attachment.nil?

    if attachment.virus_scanner.safe? || attachment.virus_scanner.pending?
      attachment.url
    end
  end

  def champ_blank?(champ) = champ.piece_justificative_file.blank?

  def columns(procedure:, displayable: true, prefix: nil)
    cs = [
      Columns::AttachedManyColumn.new(
        procedure_id: procedure.id,
        stable_id:,
        tdc_type: type_champ,
        label: libelle_with_prefix(prefix),
        type: TypeDeChamp.column_type(type_champ),
        displayable: false,
        filterable: false,
        mandatory: mandatory?
      )
    ]

    if RIB?
      cs += [
        ['Titulaire', '$.rib.account_holder'],
        ['IBAN', '$.rib.iban'],
        ['BIC', '$.rib.bic'],
        ['Nom de la Banque', '$.rib.bank_name']
      ].map do |label, jsonpath|
        Columns::JSONPathColumn.new(
         procedure_id: procedure.id,
         stable_id:,
         tdc_type: type_champ,
         label: "#{libelle_with_prefix(prefix)} – #{label}",
         type: :text,
         jsonpath:,
         displayable: true,
         mandatory: mandatory?
       )
      end
    end

    cs
  end
end
