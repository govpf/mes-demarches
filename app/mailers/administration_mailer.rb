# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/administration_mailer
class AdministrationMailer < ApplicationMailer
  layout 'mailers/layout'

  def invite_admin(user, reset_password_token)
    @reset_password_token = reset_password_token
    @user = user
    @author_name = "Équipe de #{APPLICATION_NAME}"
    subject = "Activez votre compte administrateur"

    bypass_unverified_mail_protection!

    mail(to: user.email,
      subject: subject,
      reply_to: CONTACT_EMAIL)
  end

  def refuse_admin(admin_email)
    subject = "Votre demande de compte a été refusée"

    bypass_unverified_mail_protection!

    mail(to: admin_email,
      subject: subject,
      reply_to: CONTACT_EMAIL)
  end

  def procedure_published(procedure)
    @procedure = procedure
    subject = "Une nouvelle démarche vient d'être publiée"
    mail(to: EQUIPE_EMAIL, subject: subject)
  end

  private

  def self.critical_email?(action_name)
    false
  end
end
