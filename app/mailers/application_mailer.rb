# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  include MailerMonitoringConcern
  include PriorityDeliveryConcern

  helper MailerHelper

  helper :application # gives access to all helpers defined within `application_helper`.
  # pf: constante, comme upstream depuis la suppression de MailerDefaultsConfigurableConcern
  # (2025-12-22-01) — Current.application_name vaut nil au chargement de la classe.
  default from: "#{APPLICATION_NAME} <#{CONTACT_EMAIL}>"
  layout 'mailer'

  before_action -> { Sentry.set_tags(mailer: mailer_name, action: action_name) }
end
