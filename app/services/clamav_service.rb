class ClamavService
  def self.safe_file?(file_path)
    if Rails.env.development?
      return true
    end

    client = ClamAV::Client.new
    response = client.execute(ClamAV::Commands::InstreamCommand.new(File.open(file_path, 'rb')))
    if response.class == ClamAV::SuccessResponse
      true
    elsif response.class == ClamAV::VirusResponse
      false
    elsif response.class == ClamAV::ErrorResponse
      raise "ClamAV ErrorResponse : #{response.error_str}"
    else
      raise "ClamAV unkown response #{response.class.name}"
    end
  end
end
