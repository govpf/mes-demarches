# frozen_string_literal: true

require 'base64' # pf: pour conversion data URI

# pf: Présentation des pièces jointes pour attestation v2
# Gère l'affichage des images et documents en format TipTap
class ChampPresentations::PieceJustificativePresentation < ChampPresentations::BasePresentation
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::OutputSafetyHelper
  def initialize(attachment, is_image: false, champ: nil, index: 0)
    @attachment = attachment
    @attachment_id = attachment.blob.id # pf: utiliser l'ID du blob, pas de l'attachment
    @display_name = escape_once(attachment.filename.to_s) # pf: échapper dès l'initialisation
    @champ = champ
    @index = index
    @is_image = is_image

    # pf: URL pour liens (protégée par authentification)
    @url = if champ.present?
      download_url(champ, index)
    else
      attachment.url
    end

    # pf: data URI pour images (variant 400x400 → base64, fonctionne partout sans authentification)
    @image_src = is_image ? image_to_data_uri(attachment) : nil
  end

  def to_tiptap_node
    # pf: norme upstream = clés symbol
    if @is_image
      {
        type: 'attachmentImage',
        attrs: {
          id: @attachment_id,
          src: @image_src, # pf: data URI pour affichage <img> (sans authentification)
          href: @url, # pf: URL pour lien <a> téléchargement (avec authentification)
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
      content_tag(:img, nil, src: @image_src, alt: @display_name,
                  style: 'max-width: 100px; max-height: 100px; height: auto; width: auto; object-fit: contain;')
    else
      content_tag(:a, @display_name, href: @url, target: '_blank',
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

  # pf: convertit une image en data URI base64 (variant 400x400 pour attestations/emails)
  def image_to_data_uri(attachment)
    # Créer variant 400x400 (même taille que preview gallery)
    variant = attachment.variant(resize_to_limit: [400, 400])

    # Télécharger l'image redimensionnée directement
    image_data = variant.processed.download

    # Convertir en base64
    base64_data = Base64.strict_encode64(image_data)

    # Générer data URI (utiliser le content_type du blob original)
    "data:#{attachment.blob.content_type};base64,#{base64_data}"
  rescue StandardError => e
    Rails.logger.warn "Impossible de convertir l'image en data URI: #{e.message}"
    # Fallback: image placeholder transparente 1x1
    "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
  end
end
