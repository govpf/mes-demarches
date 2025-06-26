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
    @champs_info = analyze_champs_info(procedure)
    @is_dubious = is_dubious_procedure?(procedure)
    @dubious_champs = get_dubious_champs(procedure) if @is_dubious

    subject = "Une nouvelle démarche vient d'être publiée"
    mail(to: EQUIPE_EMAIL, subject: subject)
  end

  def s3_synchronization_report(log)
    uploaded_stats = S3Synchronization.uploaded_stats
    @uploaded_stats = to_array(uploaded_stats)
    checked_stats = S3Synchronization.checked_stats
    @checked_stats = to_array(checked_stats)

    @status = S3Synchronization.blob_status
    @log = log

    mail(to: CONTACT_EMAIL, subject: "Statistiques de synchronisation")
  end

  private

  def to_array(tuples)
    targets = targets(tuples)
    sums = sums_by_target(targets, tuples)
    rows = formated_rows(tuples)
    sums + rows
  end

  def formated_rows(tuples)
    tuples.map { |l| [l.target, l.date.strftime('%d %B'), l.count, size_to_string(l.size)] }
  end

  def sums_by_target(targets, tuples)
    targets.map do |target|
      tuples.filter { |l| l.target == target }.reduce([target, "total", 0, 0]) do |total, l|
        total[2] += l.count
        total[3] += l.size
        total
      end
    end.map { |line| line[3] = size_to_string(line[3]); line }
  end

  def targets(tuples)
    tuples.reduce(Set.new) do |targets, line|
      targets.add(line.target)
    end
  end

  def size_to_string(size)
    if size > 1024 * 1024
      "#{(size / 1024.0 / 1024).round(2)}Mo"
    elsif size > 1024
      "#{(size / 1024.0).round(2)}ko"
    else
      "#{size.to_int}o"
    end
  end

  def analyze_champs_info(procedure)
    all_champs = procedure.active_revision.types_de_champ_public + procedure.active_revision.types_de_champ_private
    total_champs = all_champs.count
    champs_with_description = all_champs.count { |champ| champ.description.present? }

    {
      total_champs: total_champs,
      champs_with_description: champs_with_description,
      percentage_with_description: total_champs > 0 ? (champs_with_description * 100.0 / total_champs).round(1) : 0,
      champs_details: all_champs.map do |champ|
        {
          libelle: champ.libelle,
          type: champ.type_champ,
          description: champ.description.presence || "[Pas de description]",
          mandatory: champ.mandatory?
        }
      end
    }
  end

  def is_dubious_procedure?(procedure)
    procedure.active_revision.types_de_champ_public
      .where(type_champ: [TypeDeChamp.type_champs.fetch(:text), TypeDeChamp.type_champs.fetch(:textarea)])
      .exists?(["unaccent(types_de_champ.libelle) ~* unaccent(?)", DubiousProcedure.forbidden_regexp])
  end

  def get_dubious_champs(procedure)
    procedure.active_revision.types_de_champ_public
      .where(type_champ: [TypeDeChamp.type_champs.fetch(:text), TypeDeChamp.type_champs.fetch(:textarea)])
      .where("unaccent(types_de_champ.libelle) ~* unaccent(?)", DubiousProcedure.forbidden_regexp)
      .pluck(:libelle)
  end

  def self.critical_email?(action_name)
    false
  end
end
