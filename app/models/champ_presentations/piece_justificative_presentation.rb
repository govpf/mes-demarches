# frozen_string_literal: true

require 'base64' # pf: pour conversion data URI

# pf: Présentation des pièces jointes pour attestation v2
# Gère l'affichage des images et documents en format TipTap
class ChampPresentations::PieceJustificativePresentation < ChampPresentations::BasePresentation
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::OutputSafetyHelper
  def initialize(attachment, is_previewable: false, champ: nil, index: 0)
    @attachment = attachment
    @attachment_id = attachment.blob.id # pf: utiliser l'ID du blob, pas de l'attachment
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

    # pf: data URI pour preview (variant 400x400 → base64, supporte images/PDF/Word/etc.)
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
    # pf: si preview disponible ET data URI réussie, afficher image
    if @is_previewable && @image_src.present?
      content_tag(:img, nil, src: @image_src, alt: @filename,
                  style: 'max-width: 100px; max-height: 100px; height: auto; width: auto; object-fit: contain;')
    else
      # pf: fallback sur lien de téléchargement si preview échoue ou pas disponible
      content_tag(:a, 'Télécharger', href: @url, target: '_blank',
                  rel: 'noopener', title: @filename) # pf: nom du fichier dans le title pour info
    end
  end

  # pf: éviter l'échappement HTML dans TagsSubstitutionConcern
  def html_safe?
    true
  end

  def self.from_attachment(attachment, champ: nil, index: 0)
    # pf: utiliser previewable pour supporter PDF, Word, Excel, etc. en plus des images
    is_previewable = attachment.previewable? || attachment.image?
    new(attachment, is_previewable: is_previewable, champ: champ, index: index)
  end

  private

  # pf: génère URL permanente pour téléchargement (migré depuis TypeDeChamp)
  def download_url(champ, index)
    Rails.application.routes.url_helpers.champs_piece_justificative_download_url(
      { dossier_id: champ.dossier_id, stable_id: champ.stable_id, h: champ.encoded_date(:created_at), i: index, row_id: champ.row_id }
    )
  end

  # pf: convertit une image/preview en data URI base64 (400x400 pour attestations/emails)
  def preview_to_data_uri(attachment)
    # pf: Pour images : utiliser variant. Pour autres (PDF, Word, etc.) : utiliser preview
    if attachment.image?
      # Image : créer variant 400x400 (même taille que preview gallery)
      variant = attachment.variant(resize_to_limit: [400, 400])
      image_data = variant.processed.download
      content_type = attachment.blob.content_type
    else
      # PDF, Word, etc. : générer preview 400x400
      preview = attachment.preview(resize_to_limit: [400, 400])
      image_data = preview.processed.download
      content_type = 'image/png' # pf: les previews sont toujours en PNG
    end

    # Convertir en base64
    base64_data = Base64.strict_encode64(image_data)

    # Générer data URI
    "data:#{content_type};base64,#{base64_data}"
  rescue IOError
    # pf: stream fermé (variant pas encore traité ou fichier déjà lu) → retourner nil pour fallback sur lien
    Rails.logger.warn "PJ #{attachment.filename}: preview indisponible (stream fermé), fallback sur lien de téléchargement"
    nil
  rescue StandardError => e
    # pf: autre erreur (fichier manquant, format invalide, etc.) → retourner nil pour fallback sur lien
    Rails.logger.warn "PJ #{attachment.filename}: preview impossible (#{e.class.name}: #{e.message}), fallback sur lien de téléchargement"
    nil
  end
end
