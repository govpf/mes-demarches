# frozen_string_literal: true

# pf: accès à une ressource par lien de vérification. On journalise chaque accès
# (traçabilité) et on bannit temporairement une adresse qui enchaîne les jetons erronés.
module VerificationLinkAccessConcern
  extend ActiveSupport::Concern

  MAX_FAILURES = 5
  FAILURES_PERIOD = 10.minutes
  BAN_DURATION = 1.hour

  def self.ban_key(ip)
    "verification_links:#{ip}"
  end

  private

  def verification_link_granted?(record, value)
    format = record&.verification_link_match(value)
    log_verification_link(record, format)
    register_verification_link_failure(record) if format.nil?
    format.present?
  end

  def log_verification_link(record, format)
    Rails.logger.info("[lien_verification] #{record.class.name}##{record&.id} format=#{format || 'refuse'} user=#{current_user&.id} ip=#{request.remote_ip}")
  end

  def register_verification_link_failure(record)
    return if !Rack::Attack.rack_attack_enabled?

    banned = Rack::Attack::Fail2Ban.filter(VerificationLinkAccessConcern.ban_key(request.remote_ip), maxretry: MAX_FAILURES, findtime: FAILURES_PERIOD, bantime: BAN_DURATION) { true }
    if banned
      Sentry.capture_message("Liens de vérification : adresse bannie après jetons erronés", extra: { ip: request.remote_ip, user_id: current_user&.id, record: "#{record.class.name}##{record&.id}" })
    end
  end
end
