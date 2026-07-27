# frozen_string_literal: true

class Champs::ReferentielDePolynesieChamp < Champs::ReferentielChamp
  # pf: notre type est referentiel_de_polynesie, mais le controller et le concern
  # vérifient champ.referentiel? pour activer le flux inline autocomplete (ajout :data,
  # champs_to_turbo_update). On retourne true pour être traité comme un referentiel upstream.
  def referentiel?
    true
  end

  # pf: préserver le label humain dans value (upstream y met external_id)
  # pf: guard new_record? pour éviter que le fork (deep_clone) ne wipe data/value_json
  # sur les champs clonés — external_id_changed? est toujours true sur un new_record
  def clear_previous_result
    return if new_record? && data.present?
    return if @inline_data_present # pf: données inline via data=, ne pas effacer

    self.data = nil
    self.value_json = nil
    self.fetch_external_data_exceptions = []
  end

  # pf: déchiffre le blob chiffré soumis via le formulaire autocomplete (ComboBoxValueSlot field: :data)
  # Court-circuite ReferentielChamp#data= qui appelle rewrap_selected_object_in_datasource (non applicable à Baserow)
  # Suit le pattern upstream ReferentielChamp#data= : appelle propagate_prefill avant le save,
  # pour que champs_to_turbo_update inclue les champs préchargés avec leurs valeurs à jour.
  def data=(value)
    if dossier.present? && autocomplete? && value.is_a?(String) && value.present?
      begin
        json_string = MessageEncryptorService.new.decrypt_and_verify(value, purpose: :storage)
        @inline_data_present = true
        parsed = JSON.parse(json_string)
        write_attribute(:data, parsed)
        # pf: persiste value_json pour que ReferentielDisplayComponent affiche les colonnes displayable
        write_attribute(:value_json, cast_displayable_values(parsed.with_indifferent_access))
        propagate_prefill(parsed.with_indifferent_access) if dossier.present? && !new_record?
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, JSON::ParserError
        # pf: données brutes (tests, migration) — passer tel quel
        write_attribute(:data, value)
      end
    else
      write_attribute(:data, value)
    end
  end

  # pf: réinitialiser le flag après save pour ne pas bloquer clear_previous_result ultérieurement
  after_save -> { @inline_data_present = false }, if: -> { @inline_data_present }

  # pf: override pour calculer value_json tout en préservant le label dans value
  def update_external_data!(data:)
    transaction do
      update!(
        data:,
        value_json: cast_displayable_values(data.with_indifferent_access),
        fetch_external_data_exceptions: []
      )
      propagate_prefill(data)
    end
    # pf: cascade explicite des formules — data/value_json ont changé. À ce
    # jour les formules ne lisent pas encore les colonnes des référentiels
    # mais on prépare le terrain pour les évolutions futures.
    dossier.refresh_formulas_after(self)
  end

  # pf: autocomplete utilise le flux inline (pas de job) ; exact_match utilise le job asynchrone ;
  # pf: __other__ = saisie libre de drop_down_other — pas de fetch externe à tenter
  def uses_external_data?
    exact_match? && external_id != Champs::DropDownListChamp::OTHER
  end

  # pf: fallback legacy si pas encore de referentiel lié
  def fetch_external_data
    referentiel.present? ? super : fetch_external_data_legacy
  end

  def selected
    external_id
  end

  def selected_items
    if other?
      [{ label: I18n.t('shared.champs.drop_down_list.other'), value: external_id }]
    elsif external_id.present? && value.present?
      [{ label: value, value: external_id }]
    else
      []
    end
  end

  def other?
    external_id == Champs::DropDownListChamp::OTHER
  end

  def value_other
    return "" unless other?
    return "" if value == I18n.t('shared.champs.drop_down_list.other')
    value.to_s
  end

  def value_other=(text)
    write_attribute(:value, text.presence) if other?
  end

  # pf: helper pour savoir si le champ est en mode autocomplete
  def autocomplete?
    type_de_champ.referentiel&.autocomplete?
  end

  # pf: mode upstream = les données ont été columnisées dans value_json via cast_displayable_values.
  # Les anciens dossiers table_row_selector n'ont pas de value_json → mode legacy (config Baserow).
  def upstream_referentiel_mode?
    value_json.present?
  end

  # pf: colonnes à afficher côté dossier (vue _show), filtrées par la config du champ
  # (referentiel_mapping display_instructeur / display_usager) selon le profil.
  # Corrige le bug où toutes les colonnes étaient affichées : auparavant la sélection
  # se faisait via la config Baserow (#{profile}_fields), désormais absente du flux upstream.
  # Retourne un tableau de [libelle, value] ; value_json fournit les valeurs déjà castées.
  def displayable_columns_for(profile)
    mapping = if profile.to_s == 'instructeur'
      type_de_champ.referentiel_mapping_displayable_for_instructeur
    else
      type_de_champ.referentiel_mapping_displayable_for_usager
    end

    vj = Hash(value_json).with_indifferent_access
    mapping.filter_map do |jsonpath, opts|
      value = vj[jsonpath]
      next if value.nil?

      [opts[:libelle].presence || jsonpath, value]
    end
  end

  # pf: dual-mode — normalise les données entre ancien format (avec row) et nouveau format (plat)
  def normalized_data
    if data&.key?('row')
      data['row'] # ancien format
    else
      data # nouveau format plat
    end
  end

  # pf: support colonnes pour tags/exports (dual-mode)
  def referentiel_item_value(path)
    normalized_data&.dig(path.to_s)
  end

  # pf: focusable_input_id n'est plus surchargé — on utilise le comportement par défaut
  # (html_id + suffixe) pour éviter une collision d'ID avec input_group_id (html_id nu)
  # qui causait un crash coldwired "Cannot apply actions inside fragment" lors du turbo replace.

  private

  def fetch_external_data_legacy
    result = ReferentielDePolynesie::API.fetch_row(external_id)

    if result.present? && result.is_a?(Hash) && result.keys.any?
      Dry::Monads::Success(result.with_indifferent_access)
    else
      Dry::Monads::Failure(retryable: false, reason: StandardError.new('Row not found'), code: 404)
    end
  rescue StandardError => e
    Rails.logger.error("ReferentielDePolynesieChamp fetch error: #{e.class} - #{e.message}")
    Dry::Monads::Failure(retryable: false, reason: e, code: 500)
  end
end
