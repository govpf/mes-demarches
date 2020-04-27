class Freescout::FormAdapter
  attr_reader :params

  def initialize(params = {}, api = nil)
    @params = params
    @api = api || Freescout::API.new
  end

  TYPE_INFO = 'info demarche'
  TYPE_PERDU = 'usager perdu'
  TYPE_INSTRUCTION = 'info instruction'
  TYPE_AMELIORATION = 'produit'
  TYPE_AUTRE = 'autre'

  OPTIONS = [
    [I18n.t(TYPE_INFO, scope: [:support]), TYPE_INFO],
    [I18n.t(TYPE_PERDU, scope: [:support]), TYPE_PERDU],
    [I18n.t(TYPE_INSTRUCTION, scope: [:support]), TYPE_INSTRUCTION],
    [I18n.t(TYPE_AMELIORATION, scope: [:support]), TYPE_AMELIORATION],
    [I18n.t(TYPE_AUTRE, scope: [:support]), TYPE_AUTRE]
  ]

  ADMIN_TYPE_RDV = 'admin demande rdv'
  ADMIN_TYPE_QUESTION = 'admin question'
  ADMIN_TYPE_SOUCIS = 'admin soucis'
  ADMIN_TYPE_PRODUIT = 'admin suggestion produit'
  ADMIN_TYPE_DEMANDE_COMPTE = 'admin demande compte'
  ADMIN_TYPE_AUTRE = 'admin autre'

  ADMIN_OPTIONS = [
    [I18n.t(ADMIN_TYPE_QUESTION, scope: [:supportadmin]), ADMIN_TYPE_QUESTION],
    [I18n.t(ADMIN_TYPE_RDV, scope: [:supportadmin]), ADMIN_TYPE_RDV],
    [I18n.t(ADMIN_TYPE_SOUCIS, scope: [:supportadmin]), ADMIN_TYPE_SOUCIS],
    [I18n.t(ADMIN_TYPE_PRODUIT, scope: [:supportadmin]), ADMIN_TYPE_PRODUIT],
    [I18n.t(ADMIN_TYPE_DEMANDE_COMPTE, scope: [:supportadmin]), ADMIN_TYPE_DEMANDE_COMPTE],
    [I18n.t(ADMIN_TYPE_AUTRE, scope: [:supportadmin]), ADMIN_TYPE_AUTRE]
  ]

  def send_form
    create_conversation
  end

  private

  def create_conversation
    @api.create_conversation(
      params[:email],
      params[:subject],
      params[:text],
      params[:file],
      params[:phone]
    )
  end
end
