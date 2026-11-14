# frozen_string_literal: true

# pf: lot C DLNUF — préremplit un champ pièce justificative à partir d'une référence MD
# (« md:<numero_dossier>:<stable_id>[:<row_id>] », contrat 2026-11-06-contrat-referentiel-dlnuf.md §4.2).
# Les fichiers du champ source sont RATTACHÉS (même blob, aucune copie, aucun téléchargement) : le blob
# survit à la purge du dossier source tant qu'il reste rattaché ailleurs.
# La référence n'est pas un secret : le titulaire du dossier source est vérifié ici, dans MD.
# Retourne un symbole (diagnostic et tests) ; ne lève pas.
class ReferentielDePolynesie::PrefillPieceJustificative
  REFERENCE = /\Amd:(\d+):(\d+)(?::([A-Za-z0-9_-]+))?\z/
  TYPE_PJ = TypeDeChamp.type_champs.fetch(:piece_justificative)

  def initialize(referentiel_champ:, cible:, reference:)
    @referentiel_champ = referentiel_champ
    @cible = cible
    @reference = reference.to_s.strip
  end

  def call
    resultat = executer_sans_lever
    Rails.logger.info("ReferentielDePolynesie::PrefillPieceJustificative #{resultat} (dossier #{@cible.dossier_id}, source #{@source&.id})")
    resultat
  end

  private

  # pf: ne jamais casser l'autosave (inline) ni le job (exact_match) pour un préremplissage
  def executer_sans_lever
    executer
  rescue StandardError => e
    Sentry.capture_exception(e, extra: { cible_dossier_id: @cible.dossier_id, reference: @reference })
    :erreur
  end

  def executer
    return :non_dlnuf unless ReferentielDePolynesie::API.dlnuf_config(@referentiel_champ.table_id).is_a?(Hash)
    return :cible_interdite if @cible.type_de_champ.titre_identite_nature? # jamais un titre d'identité en cible
    return remplacer([]) if @reference.empty?

    match = REFERENCE.match(@reference)
    return :reference_illisible if match.nil?

    numero, stable_id, row_id = match.captures
    @source = Dossier.visible_by_user.where.not(state: Dossier.states.fetch(:brouillon)).find_by(id: numero.to_i)
    return :source_introuvable if @source.nil? || @source.id == @cible.dossier_id

    titulaire = verifier_titulaire
    return titulaire if titulaire

    remplacer(blobs_source(stable_id.to_i, row_id))
  end

  def verifier_titulaire
    email_source = @source.user&.email
    email_cible = @cible.dossier.user&.email
    return :autre_titulaire if email_source.blank? || email_cible.blank?
    return nil if email_source.casecmp?(email_cible)

    # pf: signal de sécurité — référence forgée ou ligne Baserow mal attribuée
    Sentry.capture_message('ReferentielDePolynesie: référence de PJ d’un autre titulaire', extra: { cible_dossier_id: @cible.dossier_id, source_dossier_id: @source.id })
    :autre_titulaire
  end

  def blobs_source(stable_id, row_id)
    tdc = @source.revision.types_de_champ.find { _1.stable_id == stable_id }
    return [] if tdc.nil? || tdc.type_champ != TYPE_PJ || tdc.titre_identite_nature? # jamais un titre d'identité
    return [] if tdc.private? # jamais une annotation privée (pièce de l'administration)
    return [] if tdc.child?(@source.revision) != row_id.present? # référence incohérente avec la structure

    cible_tdc = @cible.type_de_champ
    @source.project_champ(tdc, row_id:).piece_justificative_file.blobs.reject do |blob|
      blob.virus_scanner_error? ||
        cible_tdc.allowed_content_types.exclude?(blob.content_type) || # formats acceptés par la cible
        blob.byte_size > cible_tdc.max_file_size_bytes
    end
  end

  # Idempotence (spec §5.3) : on ne remplace que si la cible est vide ou préremplie.
  def remplacer(blobs)
    fichiers = @cible.piece_justificative_file
    return :cible_manuelle if fichiers.attached? && !@cible.prefilled?

    fichiers.purge_later if fichiers.attached? # le blob partagé survit s'il reste rattaché ailleurs
    blobs.each { fichiers.attach(_1) }
    @cible.update!(prefilled: blobs.any?)
    blobs.any? ? :rattache : :vide
  end
end
