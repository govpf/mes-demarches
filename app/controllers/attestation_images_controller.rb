# frozen_string_literal: true

# pf: Proxy pour servir les images Active Storage à WeasyPrint
class AttestationImagesController < ApplicationController
  # GET /attestation_images/proxy?blob_token=xxx
  def proxy
    blob_token = params[:blob_token] || params[:blob_id]

    begin
      # Décoder le token Active Storage pour obtenir l'ID du blob
      if blob_token.length > 10 # C'est un token
        decoded_data = Rails.application.message_verifier('ActiveStorage').verify(blob_token)
        blob_id = decoded_data['message']
      else
        blob_id = blob_token # C'est un ID direct
      end

      blob = ActiveStorage::Blob.find(blob_id)

      # Télécharger l'image et la servir avec les bons headers
      image_data = blob.download

      send_data image_data,
                type: blob.content_type,
                disposition: 'inline',
                filename: blob.filename.to_s

    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue => e
      Rails.logger.error "Erreur proxy image: #{e.message}"
      head :internal_server_error
    end
  end
end
