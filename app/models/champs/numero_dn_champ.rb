class Champs::NumeroDnChamp < Champ
  store_accessor :value_json, :numero_dn, :date_de_naissance
  store_accessor :data, :numero_dn_success

  after_validation :update_external_id

  def displayed_date_de_naissance
    ddn = date_de_naissance
    ddn.present? ? Date.parse(ddn).strftime('%d/%m/%Y') : ''
  end

  def to_s
    blank? ? "" : "#{for_tag(:value)} né(e) le #{for_tag(:date_de_naissance)}"
  end

  def numero_dn_input_id
    "#{input_id}-numero_dn"
  end

  def date_de_naissance_input_id
    "#{input_id}-date_de_naissance"
  end

  def focusable_input_id
    numero_dn_input_id
  end

  def numero_dn_success?
    numero_dn_success == true
  end

  def numero_dn_error?
    numero_dn_success == false
  end

  def blank?
    numero_dn_success != true
  end

  def fetch_external_data?
    true
  end

  def poll_external_data?
    true
  end

  def fetch_external_data
    NumeroDnService.new.(numero_dn:, date_de_naissance:)
  end

  def search_terms
    [numero_dn, displayed_date_de_naissance]
  end

  private

  def update_external_id
    if numero_dn_changed? || date_de_naissance_changed?
      if numero_dn.present? && date_de_naissance.present? && /\d{6,7}/.match?(numero_dn)
        self.external_id = { numero_dn:, date_de_naissance: }.to_json
      else
        self.external_id = nil
      end
    end
  end
end
