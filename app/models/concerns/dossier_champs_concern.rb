# frozen_string_literal: true

module DossierChampsConcern
  extend ActiveSupport::Concern

  def project_champ(type_de_champ, row_id: nil)
    check_valid_row_id_on_read?(type_de_champ, row_id)
    champ = champs_by_public_id[type_de_champ.public_id(row_id)]
    projected = if champ.nil? || !champ.is_type?(type_de_champ.type_champ)
      value = type_de_champ.champ_blank?(champ) ? nil : champ.value
      updated_at = champ&.updated_at || depose_at || created_at
      rebased_at = champ&.rebased_at
      type_de_champ.build_champ(dossier: self, row_id:, updated_at:, rebased_at:, value:, stream:)
    else
      champ.type_de_champ = type_de_champ
      champ
    end

    # pf: recalcul en mémoire des champs formule dans deux situations :
    #
    # 1. Révision brouillon (preview, dossier de test) : la révision mute en
    #    permanence — l'admin édite la procédure en direct. Les valeurs
    #    persistées peuvent être obsolètes (expression modifiée, source
    #    ajoutée/supprimée). On recalcule systématiquement.
    #
    # 2. Champ non encore persisté (new_record?) : après un rebase ou une
    #    création lazy, le champ formule n'a pas de ligne en BDD. On calcule
    #    sa valeur à la lecture pour que l'affichage soit correct, même si
    #    le rebase n'a pas créé le champ (filet de sécurité pour les dossiers
    #    rebasés avant le fix du rebase).
    #
    # Les dossiers sur révision publiée avec champ déjà persisté ne sont pas
    # concernés : refresh_dependent_formulas garde leur valeur à jour.
    #
    # Garde contre la récursion : FormulaCalculationService passe par
    # project_champs_*_all → project_champ pour construire sa vue du dossier.
    # Sans garde, le recalcul déclencherait un nouveau recalcul sur les mêmes
    # champs, à l'infini. On ne recalcule que pour le premier appel entrant.
    if type_de_champ.formule? && !Thread.current[:dossier_champs_formule_recomputing] && (revision&.draft? || projected.new_record?) && projected.respond_to?(:compute_value_from_formula)
      Thread.current[:dossier_champs_formule_recomputing] = true
      begin
        projected.value = projected.compute_value_from_formula
      ensure
        Thread.current[:dossier_champs_formule_recomputing] = nil
      end
    end

    projected
  end

  def project_champs_public
    @project_champs_public ||= revision.types_de_champ_public.map { project_champ(_1) }
  end

  def project_champs_private
    @project_champs_private ||= revision.types_de_champ_private.map { project_champ(_1) }
  end

  def project_champs
    project_champs_public + project_champs_private
  end

  def filled_champs_public
    @filled_champs_public ||= project_champs_public.flat_map do |champ|
      if champ.repetition?
        champ.rows.flatten.filter { _1.persisted? && _1.fillable? }
      elsif champ.persisted? && champ.fillable?
        champ
      else
        []
      end
    end
  end

  def filled_champs_private
    @filled_champs_private ||= project_champs_private.flat_map do |champ|
      if champ.repetition?
        champ.rows.flatten.filter { _1.persisted? && _1.fillable? }
      elsif champ.persisted? && champ.fillable?
        champ
      else
        []
      end
    end
  end

  def filled_champs
    filled_champs_public + filled_champs_private
  end

  def project_champs_public_all
    revision.types_de_champ_public.flat_map do |type_de_champ|
      champ = project_champ(type_de_champ)
      if type_de_champ.repetition?
        [champ] + project_rows_for(type_de_champ).flatten
      else
        champ
      end
    end
  end

  def project_champs_private_all
    revision.types_de_champ_private.flat_map do |type_de_champ|
      champ = project_champ(type_de_champ)
      if type_de_champ.repetition?
        [champ] + project_rows_for(type_de_champ).flatten
      else
        champ
      end
    end
  end

  def project_rows_for(type_de_champ)
    return [] if !type_de_champ.repetition?

    children = revision.children_of(type_de_champ)
    row_ids = repetition_row_ids(type_de_champ)

    row_ids.map do |row_id|
      children.map { project_champ(_1, row_id:) }
    end
  end

  def find_type_de_champ_by_stable_id(stable_id, scope = nil)
    case scope
    when :public
      revision.types_de_champ.filter(&:public?)
    when :private
      revision.types_de_champ.filter(&:private?)
    else
      revision.types_de_champ
    end.find { _1.stable_id == stable_id.to_i }
  end

  def champs_for_prefill(stable_ids)
    revision
      .types_de_champ
      .filter { _1.stable_id.in?(stable_ids) }
      .filter { !_1.child?(revision) }
      .map { _1.repetition? ? project_champ(_1) : champ_for_update(_1, updated_by: nil) }
  end

  def champ_value_for_tag(type_de_champ, path = :value)
    champ = if type_de_champ.repetition?
      project_champ(type_de_champ)
    else
      filled_champ(type_de_champ)
    end
    type_de_champ.champ_value_for_tag(champ, path)
  end

  def champ_for_update(type_de_champ, row_id: nil, updated_by:)
    champ = champ_upsert_by!(type_de_champ, row_id)
    champ.updated_by = updated_by
    champ
  end

  def public_champ_for_update(public_id, updated_by:)
    return nil if public_id.nil?
    stable_id, row_id = public_id.split('-')
    type_de_champ = find_type_de_champ_by_stable_id(stable_id, :public)
    champ_for_update(type_de_champ, row_id:, updated_by:)
  end

  def private_champ_for_update(public_id, updated_by:)
    return nil if public_id.nil?
    stable_id, row_id = public_id.split('-')
    type_de_champ = find_type_de_champ_by_stable_id(stable_id, :private)
    champ_for_update(type_de_champ, row_id:, updated_by:)
  end

  def repetition_rows_for_export(type_de_champ)
    repetition_row_ids(type_de_champ).map.with_index(1) do |row_id, index|
      Champs::RepetitionChamp::Row.new(index:, row_id:, dossier: self)
    end
  end

  def repetition_row_ids(type_de_champ)
    return [] if !type_de_champ.repetition?
    @repetition_row_ids ||= {}
    @repetition_row_ids[type_de_champ.stable_id] ||= champs_on_stream
      .filter { _1.row? && _1.stable_id == type_de_champ.stable_id && !_1.discarded? }
      .map(&:row_id)
      .sort
  end

  def repetition_add_row(type_de_champ, updated_by:)
    raise "Can't add row to non-repetition type de champ" if !type_de_champ.repetition?

    row_id = ULID.generate
    champ_for_update(type_de_champ, row_id:, updated_by:)
    row_id
  end

  def repetition_remove_row(type_de_champ, row_id, updated_by:)
    raise "Can't remove row from non-repetition type de champ" if !type_de_champ.repetition?

    champ = champ_for_update(type_de_champ, row_id:, updated_by:)
    champ.discard!
  end

  def stable_id_in_revision?(stable_id)
    revision_stable_ids.member?(stable_id.to_i)
  end

  def reload
    super.tap { reset_champs_cache }
  end

  def merge_user_buffer_stream!
    buffer_champ_ids_h = champs.where(stream: Champ::USER_BUFFER_STREAM, stable_id: revision_stable_ids)
      .pluck(:id, :stable_id, :row_id)
      .index_by { |(_, stable_id, row_id)| TypeDeChamp.public_id(stable_id, row_id) }
      .transform_values(&:first)

    return if buffer_champ_ids_h.empty?

    discarded_row_ids = champs.where(stream: Champ::USER_BUFFER_STREAM, stable_id: revision_stable_ids)
      .where.not(row_id: nil)
      .where.not(discarded_at: nil)
      .pluck(:row_id)

    changed_main_champ_ids_h = champs.where(stream: Champ::MAIN_STREAM, stable_id: revision_stable_ids)
      .pluck(:id, :stable_id, :row_id)
      .index_by { |(_, stable_id, row_id)| TypeDeChamp.public_id(stable_id, row_id) }
      .transform_values(&:first)

    buffer_champ_ids = buffer_champ_ids_h.values
    changed_main_champ_ids = changed_main_champ_ids_h.filter_map { |public_id, id| id if buffer_champ_ids_h.key?(public_id) }.to_set

    now = Time.zone.now
    history_stream = "#{Champ::HISTORY_STREAM}#{now}"
    changed_champs = champs.filter { _1.id.in?(buffer_champ_ids) }

    if discarded_row_ids.present?
      changed_main_champ_ids += champs.where(stream: Champ::MAIN_STREAM, row_id: discarded_row_ids).pluck(:id)
    end

    transaction do
      champs.where(id: changed_main_champ_ids, stream: Champ::MAIN_STREAM).update_all(stream: history_stream)
      champs.where(id: buffer_champ_ids, stream: Champ::USER_BUFFER_STREAM).update_all(stream: Champ::MAIN_STREAM, updated_at: now)
      update_champs_timestamps(changed_champs)
    end

    champs.where(id: changed_main_champ_ids, stream: history_stream)
      .where(type: ['Champs::PieceJustificativeChamp', 'Champs::TitreIdentiteChamp'])
      .with_attached_piece_justificative_file.find_each do |champ|
      files = champ.piece_justificative_file.map { _1.slice(:filename, :checksum) }
      if files.present?
        champ.update_column(:data, files)
        champ.piece_justificative_file.purge_later
      end
    end

    # update loaded champ instances
    champs.each do |champ|
      if champ.id.in?(changed_main_champ_ids)
        champ.stream = history_stream
      elsif champ.id.in?(buffer_champ_ids)
        champ.stream = Champ::MAIN_STREAM
      end
    end

    # pf: Le merge est terminé. Les buffer ont été promus à main, les
    # anciens main sont passés en history. Le dossier vit conceptuellement
    # sur main désormais — le @stream encore à user:buffer (hérité du
    # before_action :set_dossier_stream du controller) ne reflète plus rien.
    #
    # On reset les caches dérivés (champs_by_public_id, project_champs_*,
    # etc. qui pouvaient encore filtrer sur buffer) puis on aligne @stream
    # explicitement. Toute opération suivante voit un état cohérent.
    reset_champs_cache
    @stream = Champ::MAIN_STREAM

    # pf: Recalcul des formules privées après merge. Pendant que le dossier
    # était sur user:buffer, la cascade refresh_dependent_formulas a
    # explicitement skippé les formules privées (cf. check_valid_stream_on_write?
    # qui interdit l'écriture privée hors main). Maintenant que les sources
    # promues sont sur main et que @stream est aligné, on peut les recalculer.
    #
    # On cible uniquement les formules privées : les formules publiques ont
    # été calculées en cascade pendant que le dossier était en buffer (sur
    # user:buffer), puis promues à main par l'update_all ci-dessus.
    private_formula_stable_ids = revision.types_de_champ_private
      .filter(&:formule?)
      .map(&:stable_id)
    compute_formulas_in_order(only: private_formula_stable_ids) if private_formula_stable_ids.any?
  end

  def reset_user_buffer_stream!
    champs.where(stream: Champ::USER_BUFFER_STREAM).destroy_all

    # update loaded champ instances
    association(:champs).target = champs.filter { _1.stream != Champ::USER_BUFFER_STREAM }

    reset_champs_cache
  end

  def user_buffer_changes?
    champs_on_user_buffer_stream.present?
  end

  def user_buffer_changes_on_champ?(champ)
    champs_on_user_buffer_stream.any? { _1.public_id == champ.public_id }
  end

  def with_update_stream(user, &block)
    if en_construction? && user.owns_or_invite?(self)
      with_stream(Champ::USER_BUFFER_STREAM, &block)
    else
      with_stream(Champ::MAIN_STREAM, &block)
    end
  end

  def with_main_stream(&block)
    with_stream(Champ::MAIN_STREAM, &block)
  end

  def with_champ_stream(champ, &block)
    with_stream(champ.stream, &block)
  end

  def stream
    @stream || Champ::MAIN_STREAM
  end

  def history
    champs_in_revision.filter(&:history_stream?)
  end

  # pf: méthode publique nécessaire pour éviter boucle infinie dans les conditions
  # voir ChampConditionalConcern#champs_for_condition
  def champs_by_public_id_for_conditions
    champs_by_public_id.values
  end

  private

  def with_stream(stream)
    if block_given?
      previous_stream = @stream
      @stream = stream
      reset_champs_cache
      result = yield
      @stream = previous_stream
      reset_champs_cache
      result
    else
      @stream = stream
      reset_champs_cache
      self
    end
  end

  def champs_by_public_id
    @champs_by_public_id ||= champs_on_stream.index_by(&:public_id)
  end

  def discarded_champs_by_public_id
    @discarded_champs_by_public_id ||= discarded_champs_on_main_stream.index_by(&:public_id)
  end

  def champs_on_stream
    @champs_on_stream ||= case stream
    when Champ::USER_BUFFER_STREAM
      (champs_on_user_buffer_stream + champs_on_main_stream).uniq(&:public_id)
    else
      champs_on_main_stream
    end
  end

  def revision_stable_ids
    @revision_stable_ids ||= revision.types_de_champ.map(&:stable_id).to_set
  end

  def champs_in_revision
    champs.filter { stable_id_in_revision?(_1.stable_id) }
  end

  def discarded_champs_on_main_stream
    champs.filter(&:main_stream?).reject { stable_id_in_revision?(_1.stable_id) }
  end

  def champs_on_main_stream
    champs_in_revision.filter(&:main_stream?)
  end

  def champs_on_user_buffer_stream
    champs_in_revision.filter(&:user_buffer_stream?)
  end

  def filled_champ(type_de_champ, row_id: nil, with_discarded: false)
    champ_public_id = type_de_champ.public_id(row_id)
    champ = champs_by_public_id[champ_public_id]

    if champ.nil? && with_discarded
      champ = discarded_champs_by_public_id[champ_public_id]
    end

    return nil if type_de_champ.champ_blank?(champ)

    if discarded_champs_by_public_id.key?(champ_public_id)
      champ
    elsif !champ.visible?
      nil
    else
      champ
    end
  end

  private

  def champ_attributes_by_public_id(public_id, attributes, scope, updated_by:)
    stable_id, row_id = public_id.split('-')
    type_de_champ = find_type_de_champ_by_stable_id(stable_id, scope)
    champ = champ_upsert_by!(type_de_champ, row_id)
    attributes.merge(id: champ.id, updated_by:)
  end

  # pf: system_write: true → bypass du check stream pour les écritures
  # système (ex: rebase qui matérialise une formule publique en main alors
  # que le dossier est en_construction). Les écritures déclenchées par une
  # action user/instructeur doivent toujours laisser le check actif.
  def champ_upsert_by!(type_de_champ, row_id, system_write: false)
    check_valid_stream_on_write?(type_de_champ) unless system_write
    check_valid_row_id_on_write?(type_de_champ, row_id)

    # FIXME: This is a temporary on-demand migration. It will be removed once the full migration is over.
    Champ.where(dossier_id: id, row_id: Champ::NULL_ROW_ID).update_all(row_id: nil)

    # FIXME: Try to find the champ in memory before querying the database
    champ = champs.find { _1.stream == stream && _1.public_id == type_de_champ.public_id(row_id) }

    if champ.nil?
      champ = Dossier.no_touching do
        champs
          .create_with(**type_de_champ.params_for_champ)
          .create_or_find_by!(stable_id: type_de_champ.stable_id, row_id:, stream:)
      end
    end

    # Needed when a revision change the champ type in this case, we reset the champ data
    needs_clone_from_main = false
    if champ.class != type_de_champ.champ_class
      champ = champ.becomes!(type_de_champ.champ_class)
      champ.assign_attributes(value: nil, value_json: nil, external_id: nil, data: nil)
    elsif stream != Champ::MAIN_STREAM && champ.previously_new_record?
      needs_clone_from_main = true
    end

    # maj de champs
    loaded_champ = champs.find { [_1.stream, _1.public_id] == [champ.stream, champ.public_id] }
    if loaded_champ.nil?
      # pf for race conditions only, multi-thread update of same champ
      association(:champs).target.push(champ) if champs.loaded?
    elsif loaded_champ.object_id != champ.object_id
      association(:champs).target = champs - [loaded_champ] + [champ]
    end
    # pf: rattacher le Champ à self AVANT toute opération qui déclenche la
    # cascade (clone_value_from → save! → refresh_dependent_formulas). Sinon
    # la cascade lit champ.dossier qui pointe sur l'instance Dossier
    # fantôme matérialisée par create_or_find_by!, et tous les Champs
    # formule créés en cascade s'attachent à ce fantôme — invisibles pour
    # le contrôleur qui retravaille avec self. Au 2e save (re-cascade
    # via assign_attributes + save), self.champs ne les contient pas et
    # create_or_find_by! ne détecte pas le doublon en BDD car la contrainte
    # unique sur (dossier_id, stream, stable_id, row_id) ne matche pas
    # quand row_id IS NULL → INSERT crée un doublon.
    if champ.dossier.object_id != object_id
      champ.association(:dossier).target = self
    end
    reset_champs_cache

    if needs_clone_from_main
      main_stream_champ = champs.find_by(stable_id: type_de_champ.stable_id, row_id:, stream: Champ::MAIN_STREAM)
      champ.clone_value_from(main_stream_champ) if main_stream_champ.present?
    else
      champ.save!
    end

    champ
  end

  def check_valid_stream_on_write?(type_de_champ)
    if type_de_champ.private?
      if stream != Champ::MAIN_STREAM
        raise "Can not write a private champ to \"#{stream}\" stream"
      end
    elsif stream == Champ::MAIN_STREAM && en_construction?
      raise 'Can not write to "main" stream on a dossier "en construction"'
    end
  end

  def check_valid_row_id_on_write?(type_de_champ, row_id)
    if type_de_champ.repetition?
      if row_id.blank?
        raise "type_de_champ #{type_de_champ.stable_id} in revision #{revision_id} must have a row_id because it represents a row in a repetition"
      end
    else
      check_valid_row_id_on_read?(type_de_champ, row_id)
    end
  end

  def check_valid_row_id_on_read?(type_de_champ, row_id)
    if type_de_champ.child?(revision)
      if row_id.blank?
        raise "type_de_champ #{type_de_champ.stable_id} in revision #{revision_id} must have a row_id because it is part of a repetition"
      end
    elsif row_id.present? && stable_id_in_revision?(type_de_champ.stable_id)
      raise "type_de_champ #{type_de_champ.stable_id} in revision #{revision_id} can not have a row_id because it is not part of a repetition"
    end
  end

  def reset_champs_cache
    @champs_by_public_id = nil
    @discarded_champs_by_public_id = nil
    @filled_champs_public = nil
    @filled_champs_private = nil
    @project_champs_public = nil
    @project_champs_private = nil
    @repetition_row_ids = nil
    @revision_stable_ids = nil
    @champs_on_stream = nil
  end
end
