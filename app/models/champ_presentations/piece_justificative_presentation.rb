# frozen_string_literal: true

# pf: Présentation des pièces jointes pour attestation v2
# Gère l'affichage des images et documents en format TipTap
class ChampPresentations::PieceJustificativePresentation < ChampPresentations::BasePresentation
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::OutputSafetyHelper
  def initialize(attachment, is_image: false, champ: nil, index: 0)
    @attachment = attachment
    @attachment_id = attachment.blob.id # pf: utiliser l'ID du blob, pas de l'attachment
    @display_name = attachment.filename.to_s
    @champ = champ
    @index = index
    @is_image = is_image

    # pf: générer URL permanente comme dans v1
    @url = if champ.present?
      download_url(champ, index)
    elsif Rails.env.development? && is_image
      Rails.application.routes.url_helpers.attestation_images_proxy_path(blob_id: attachment.blob.id)
    else
      attachment.url
    end
  end

  def to_tiptap_node
    if @is_image
      {
        type: 'attachmentImage',
        attrs: {
          id: @attachment_id,
          src: @url,
          alt: @display_name,
          display: @display_name
        }
      }
    else
      {
        type: 'attachmentLink',
        attrs: { href: @url, target: '_blank', rel: 'noopener' },
        content: [{ type: 'text', text: @display_name }]
      }
    end
  end

  def to_s
    if @is_image
      content_tag(:img, nil, src: @url, alt: @display_name,
                  style: 'max-width: 100px; max-height: 100px; height: auto; width: auto; object-fit: contain;')
    else
      content_tag(:a, escape_once(@display_name), href: @url, target: '_blank',
                  rel: 'noopener', title: 'Télécharger la pièce jointe')
    end
  end

  # pf: éviter l'échappement HTML dans TagsSubstitutionConcern
  def html_safe?
    true
  end

  def self.from_attachment(attachment, champ: nil, index: 0)
    is_image = attachment.image?
    new(attachment, is_image: is_image, champ: champ, index: index)
  end

  private

  # pf: génère URL permanente pour téléchargement (migré depuis TypeDeChamp)
  def download_url(champ, index)
    Rails.application.routes.url_helpers.champs_piece_justificative_download_url(
      { dossier_id: champ.dossier_id, stable_id: champ.stable_id, h: champ.encoded_date(:created_at), i: index, row_id: champ.row_id }
    )
  end
end
