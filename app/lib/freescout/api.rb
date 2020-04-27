class Freescout::API
  def ready?
    false
  end

  def add_tags(conversation_id, tags)
    Rails.logger.warn("[FreeScout API] add phone number not available")
  end

  def create_conversation(email, subject, text, file, phone = "")
    AdministrationMailer.post_ticket(email, subject, text, attachments(file), phone).deliver_later
  end

  def add_phone_number(email, phone)
    Rails.logger.warn("[FreeScout API] add phone number not available")
  end

  def productivity_report(year, month)
    Rails.logger.warn("[FreeScout API] productivity report not available for #{month}-#{year}…")
    {}
  end

  private

  def attachments(file)
    if file.present?
      [
        {
          fileName: file.original_filename,
          mime_type: file.content_type,
          content: file.read
        }
      ]
    else
      []
    end
  end

  def customer(email)
    {
      email: email
    }
  end
end
