# frozen_string_literal: true

require 'resolv'
require 'addressable/uri'

class WebHookJob < ApplicationJob
  queue_as :default

  TIMEOUT = 10

  def perform(procedure_id, dossier_id, state, updated_at)
    procedure = Procedure.find(procedure_id)

    if unsafe_url?(procedure.web_hook_url)
      Sentry.set_tags(procedure: procedure_id, dossier: dossier_id)
      Sentry.set_extras(web_hook_url: procedure.web_hook_url)
      Sentry.capture_message("Webhook SSRF blocked: #{procedure.web_hook_url} resolves to a private IP")
      return
    end

    body = {
      procedure_id: procedure_id,
      dossier_id: dossier_id,
      state: state,
      updated_at: updated_at,
    }

    response = Typhoeus.post(procedure.web_hook_url, body: body, timeout: TIMEOUT)

    if !response.success?
      Sentry.set_tags(procedure: procedure_id, dossier: dossier_id)
      Sentry.set_extras(web_hook_url: procedure.web_hook_url)
      Sentry.capture_message("Webhook error code: #{response.code} (#{response.return_message}) // Response: #{response.body}")
    end
  end

  private

  def unsafe_url?(url)
    return true if url.blank?

    uri = Addressable::URI.parse(url)
    host = uri&.host
    return true if host.blank?

    addresses = Resolv.getaddresses(host)
    return true if addresses.empty?

    addresses.any? { NoPrivateIPURLValidator.private_ip?(_1) }
  rescue Addressable::URI::InvalidURIError, Resolv::ResolvError
    true
  end
end
