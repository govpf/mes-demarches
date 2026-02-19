# frozen_string_literal: true

require 'base64' # pf: pour conversion data URI

# pf: Présentation des pièces jointes pour attestation v2
# Gère l'affichage des images et documents en format TipTap
class ChampPresentations::PieceJustificativePresentation < ChampPresentations::BasePresentation
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::OutputSafetyHelper
  def initialize(attachment, is_previewable: false, champ: nil, index: 0)
    @attachment = attachment
    @attachment_id = attachment.id # pf: ID de l'attachment (requis par Prawn show.pdf.prawn:51)
    @filename = escape_once(attachment.filename.to_s) # pf: garder le nom original pour le titre
    @champ = champ
    @index = index
    @is_previewable = is_previewable

    # pf: URL pour liens (protégée par authentification)
    @url = if champ.present?
      download_url(champ, index)
    else
      attachment.url
    end

    # pf: data URI pour preview (variant 400x400 → base64, images uniquement)
    @image_src = is_previewable ? preview_to_data_uri(attachment) : nil
  end

  def to_tiptap_node
    # pf: norme upstream = clés symbol
    # pf: si preview disponible ET data URI réussie, afficher image
    if @is_previewable && @image_src.present?
      {
        type: 'attachmentImage',
        attrs: {
          id: @attachment_id,
          src: @image_src, # pf: data URI pour affichage <img> (sans authentification)
          href: @url, # pf: URL pour lien <a> téléchargement (avec authentification)
          alt: @filename, # pf: nom du fichier pour accessibilité
          display: 'Télécharger' # pf: texte court et universel
        }
      }
    else
      # pf: fallback sur lien de téléchargement si preview échoue ou pas disponible
      {
        type: 'attachmentLink',
        attrs: { href: @url, target: '_blank', rel: 'noopener' },
        content: [{ type: 'text', text: "Télécharger #{@filename}" }] # pf: afficher le nom du fichier
      }
    end
  end

  def to_s
    # pf: si preview disponible ET data URI réussie, afficher image + lien
    if @is_previewable && @image_src.present?
      image = content_tag(:img, nil, id: @attachment_id, src: @image_src, alt: @filename,
                          style: 'max-width: 100px; max-height: 100px; height: auto; width: auto; object-fit: contain; display: block; margin-bottom: 5px;')
      link = content_tag(:a, "Télécharger", href: @url, target: '_blank', rel: 'noopener')
      safe_join([image, link])
    else
      # pf: sinon juste le lien
      content_tag(:a, "Télécharger #{@filename}", href: @url, target: '_blank', rel: 'noopener')
    end
  end

  # pf: éviter l'échappement HTML dans TagsSubstitutionConcern
  def html_safe?
    true
  end

  def self.from_attachment(attachment, champ: nil, index: 0)
    # pf: seules les images sont affichées inline dans les attestations.
    # Les PDF/Word/etc. ne génèrent plus de preview pour éviter le bug Rails
    # où le Tempfile est GC avant l'upload S3 (après_commit différé dans la transaction accepter).
    is_previewable = attachment.image?
    new(attachment, is_previewable: is_previewable, champ: champ, index: index)
  end

  private

  # pf: génère URL permanente pour téléchargement (migré depuis TypeDeChamp)
  def download_url(champ, index)
    Rails.application.routes.url_helpers.champs_piece_justificative_download_url(
      { dossier_id: champ.dossier_id, stable_id: champ.stable_id, h: champ.encoded_date(:created_at), i: index, row_id: champ.row_id }
    )
  end

  # pf: convertit une image en data URI base64 (variant 400x400 pour attestations/emails)
  # Seules les images sont supportées. Les PDF/Word ne génèrent plus de preview inline
  # pour éviter le bug Rails Tempfile GC (rails/rails#47047).
  def preview_to_data_uri(attachment)
    variant = attachment.variant(resize_to_limit: [400, 400])
    image_data = variant.processed.download
    content_type = attachment.blob.content_type

    base64_data = Base64.strict_encode64(image_data)
    "data:#{content_type};base64,#{base64_data}"
  rescue StandardError => e
    # pf: erreur (fichier manquant Errno::ENOENT, stream fermé, format invalide, etc.)
    # → retourner nil pour fallback sur lien de téléchargement (pas de 500)
    Rails.logger.warn "PJ #{attachment.filename}: preview impossible (#{e.class.name}: #{e.message}), fallback sur lien de téléchargement"
    Rails.logger.warn e.backtrace&.first(5)&.join("\n")
    nil
  end
end
