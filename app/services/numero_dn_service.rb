class NumeroDnService
  include Dry::Monads[:result]

  def call(numero_dn:, date_de_naissance:)
    result = APICps::API.new().verify({ numero_dn => date_de_naissance })
    case result[numero_dn]
    when 'true', 'false', 'unknown dn'
      numero_dn_success = result[numero_dn] == 'true'
      Success({
        numero_dn_success:
      })
    else
      result
    end
  rescue APIEntreprise::API::Error::RequestFailed
    :network_error
  end
end
