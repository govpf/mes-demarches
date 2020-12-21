# == Schema Information
#
# Table name: champs
#
#  id               :integer          not null, primary key
#  private          :boolean          default(FALSE), not null
#  row              :integer
#  type             :string
#  value            :string
#  created_at       :datetime
#  updated_at       :datetime
#  dossier_id       :integer
#  etablissement_id :integer
#  parent_id        :bigint
#  type_de_champ_id :integer
#
class Champs::DossierLinkChamp < Champ
  validate :value, :value_cannot_be_float

  def value_cannot_be_float
    if value.to_i != value.to_f
      Raven.capture_message("Numéro de dossier avec décimales #{value}", extra: { debug: true })
    end
  end
end
