# frozen_string_literal: true

module Types
  class File < Types::BaseObject
    field :url, Types::URL, null: false
    field :filename, String, null: false
    field :byte_size, Int, null: false, deprecation_reason: "Utilisez le champ `byteSizeBigInt` à la place."
    field :byte_size_big_int, GraphQL::Types::BigInt, null: false, method: :byte_size
    field :checksum, String, null: false
    field :content_type, String, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, "Date de création du fichier.", null: false
    field :virus_scan_result, String, null: false

    def url
      if object.is_a?(Hash)
        object[:url]
      else
        # pf: stockage S3 direct → l'URL presignée est absolue et auto-suffisante.
        # Ne pas passer host: — clé invalide pour aws-sdk (ArgumentError: unexpected
        # value at params[:host]), et Current.host vaut le hostname interne du cluster
        # en requête server-to-server. cf. upstream #12346 / 3871d37538.
        object.url
      end
    end

    def virus_scan_result
      if object.is_a?(Hash)
        object[:virus_scan_result] || ActiveStorage::VirusScanner::PENDING
      else
        object.virus_scan_result || object.metadata[:virus_scan_result] || ActiveStorage::VirusScanner::PENDING
      end
    end
  end
end
