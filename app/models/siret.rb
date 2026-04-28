# frozen_string_literal: true

class Siret
  include ActiveModel::Model
  include ActiveModel::Validations::Callbacks

  attr_accessor :siret

  validates :siret, presence: true
  validates :siret, siret: true

  before_validation :remove_whitespace

  def remove_whitespace
    # pf: also strip hyphens since Tahiti numbers may be formatted as "123456-789"
    self.siret = siret.gsub(/[[:space:]-]/, "") if siret.present?
  end
end
