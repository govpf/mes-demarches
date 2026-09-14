# frozen_string_literal: true

class EditableChamp::ReferentielDePolynesieComponent < EditableChamp::EditableChampBaseComponent
  include ApplicationHelper
  include Rails.application.routes.url_helpers

  delegate :type_de_champ, to: :@champ
  delegate :referentiel, to: :type_de_champ
  delegate :exact_match?, to: :referentiel, allow_nil: true

  def dsfr_input_classname
    exact_match? ? 'fr-input' : 'fr-select'
  end

  def react_props
    table = @champ.table_id
    # pf: dossier_id — permet au serveur de résoudre le scope DLNUF (mail du titulaire) et le
    # filtre contextuel sans jamais les lire depuis le client ; ignoré pour les tables catalogue
    props = react_input_opts(id: @champ.focusable_input_id,
      class: 'fr-mt-1w',
      name: @form.field_name(:external_id),
      selectedKey: @champ.selected,
      items: @champ.selected_items,
      loader: data_sources_rdp_search_path(table:, drop_down_other: @champ.drop_down_other?, dossier_id: @champ.dossier_id, **contextual_loader_params),
      limit: 20,
      minimumInputLength: (dlnuf? || contextual_filter?) ? 0 : 2,
      data: { table_id: @champ.table_id })

    if dlnuf?
      # pf: DLNUF — « mes données » n'est pas une recherche : lister au focus, auto-remplir
      # si une seule ligne, et ne JAMAIS échoer le mail dans les messages
      props[:autoSelectSingle] = true
      props[:emptyLabel] = I18n.t('shared.champs.referentiel_de_polynesie.dlnuf_empty')
      # pf: DLNUF — champ optionnel sans donnée : masquer le champ entier (zéro friction) ;
      # obligatoire : rester affiché avec le message, le requis bloque le dépôt de toute façon
      props[:hideWhenEmpty] = !@champ.mandatory?
    end

    if contextual_filter?
      # pf: cascade — le périmètre est petit : lister au focus. JAMAIS de masquage (une erreur
      # de mapping Baserow doit rester visible) ; deux messages selon l'état du pilote.
      props[:emptyLabel] = contextual_filter.empty_label
    end
    props
  end

  private

  # pf: détection du mode DLNUF (cache court côté API). En cas d'échec Baserow ou de config
  # invalide, on retombe sur l'ergonomie catalogue — la sécurité reste côté serveur (#search).
  def dlnuf?
    return @dlnuf if defined?(@dlnuf)

    config = ReferentielDePolynesie::API.dlnuf_config(@champ.table_id)
    @dlnuf = config.present? && config != :invalid
  rescue StandardError
    @dlnuf = false
  end

  # pf: cascade — filtre contextuel résolu côté serveur pour le message d'état vide
  def contextual_filter
    return @contextual_filter if defined?(@contextual_filter)

    @contextual_filter = type_de_champ.referentiel_filter? ? ReferentielDePolynesie::ContextualFilter.for(type_de_champ:, dossier: @champ.dossier, row_id: @champ.row_id) : nil
  end

  def contextual_filter?
    contextual_filter.present? && contextual_filter.configured?
  end

  def contextual_loader_params
    return {} unless contextual_filter?

    { stable_id: @champ.stable_id, row_id: @champ.row_id, pilot_version: }.compact
  end

  # pf: cascade — cache-buster de l'URL du loader. Le composant React n'est pas remonté par le
  # re-rendu Turbo (coldwired met seulement les props à jour) et `useAsyncList` garde ses items
  # tant que l'URL de chargement est identique. Un digest court de la valeur du pilote fait
  # changer l'URL à chaque changement de pilote, ce qui déclenche le rechargement de la liste.
  # JAMAIS la valeur du pilote elle-même : elle reste résolue côté serveur.
  def pilot_version
    value = contextual_filter.pilot_value
    value.blank? ? '0' : Digest::SHA1.hexdigest(value.to_s)[0, 8]
  end
end
