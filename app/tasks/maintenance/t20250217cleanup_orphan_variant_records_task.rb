# frozen_string_literal: true

module Maintenance
  # pf: Nettoie les VariantRecords et preview_image attachments orphelins
  # dont le blob associé n'a pas de fichier sur S3.
  #
  # Contexte : VariantWithRecord#processed? vérifie la présence du record en base,
  # pas l'existence du fichier sur S3. Si l'upload S3 échoue (réseau, timeout...),
  # le record survit mais le fichier est absent. Les appels suivants à .processed
  # pensent que le variant existe et retournent une URL vers un fichier inexistant.
  #
  # Cette tâche identifie ces orphelins et supprime les records pour forcer
  # une re-génération propre au prochain appel à .processed.
  #
  # Deux types d'orphelins :
  # 1. ActiveStorage::VariantRecord → image attachée dont le blob n'est pas sur S3
  # 2. ActiveStorage::Attachment(name: "preview_image") → preview de PDF dont le blob n'est pas sur S3
  class T20250217cleanupOrphanVariantRecordsTask < MaintenanceTasks::Task
    include RunnableOnDeployConcern
    include StatementsHelpersConcern

    run_on_first_deploy

    def collection
      # Tous les blobs qui sont des variants ou des previews
      # (attachés à un VariantRecord ou en tant que preview_image d'un Blob)
      variant_blob_ids = ActiveStorage::Attachment
        .where(record_type: "ActiveStorage::VariantRecord", name: "image")
        .pluck(:blob_id)

      preview_blob_ids = ActiveStorage::Attachment
        .where(record_type: "ActiveStorage::Blob", name: "preview_image")
        .pluck(:blob_id)

      ActiveStorage::Blob.where(id: (variant_blob_ids + preview_blob_ids).uniq).in_batches(of: 100)
    end

    def process(batch_of_blobs)
      batch_of_blobs.each do |blob|
        next if blob.service.exist?(blob.key)

        Rails.logger.info "cleanup_orphan_variants: suppression blob orphelin #{blob.id} key=#{blob.key} content_type=#{blob.content_type}"

        # Supprimer le variant_record ou l'attachment preview_image qui référence ce blob
        ActiveStorage::Attachment.where(blob_id: blob.id).find_each do |attachment|
          if attachment.record_type == "ActiveStorage::VariantRecord"
            # Supprimer le VariantRecord (qui supprimera aussi l'attachment via dependent)
            attachment.record&.destroy
          else
            # Pour les preview_image : supprimer l'attachment
            attachment.destroy
          end
        end

        # Supprimer le blob orphelin lui-même
        blob.destroy
      rescue StandardError => e
        Rails.logger.warn "cleanup_orphan_variants: erreur sur blob #{blob.id} - #{e.class}: #{e.message}"
      end
    end

    def count
      with_statement_timeout("5min") do
        variant_count = ActiveStorage::Attachment
          .where(record_type: "ActiveStorage::VariantRecord", name: "image").count
        preview_count = ActiveStorage::Attachment
          .where(record_type: "ActiveStorage::Blob", name: "preview_image").count
        variant_count + preview_count
      end
    end
  end
end
