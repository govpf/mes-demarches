# frozen_string_literal: true

# pf: lot C DLNUF — règle serveur unique du mapping « pièce justificative » (éditeur web et MCP).
# Une pièce ne se préremplit que depuis une colonne de référence d'une table DLNUF, vers un champ
# pièce justificative (jamais titre_identite), à la racine ou dans la même ligne de bloc que le
# référentiel ; une référence n'est jamais affichée. Ne pas se fier au seul formulaire.
class ReferentielDePolynesie::MappingPieceJustificative
  TYPE = 'piece_justificative'
  CIBLES_PIECES = %w[piece_justificative titre_identite].freeze

  # mapping : Hash jsonpath → options (clés chaînes ou symboles). Retourne des messages, [] si valide.
  def self.erreurs(type_de_champ:, mapping:, revision:)
    new(type_de_champ:, mapping:, revision:).erreurs
  end

  def initialize(type_de_champ:, mapping:, revision:)
    @tdc = type_de_champ
    @mapping = Hash(mapping).transform_values { Hash(_1).stringify_keys }
    @revision = revision
    @tdcs = revision.types_de_champ.index_by { _1.stable_id.to_s }
  end

  def erreurs
    @mapping.flat_map do |jsonpath, opts|
      colonne = jsonpath.to_s.delete_prefix('$.')
      cible = cible_de(opts)
      if opts['type'] == TYPE
        erreurs_reference(jsonpath, colonne, opts, cible)
      elsif cible&.type_champ.in?(CIBLES_PIECES)
        ["La colonne « #{colonne} » ne peut pas préremplir le champ « #{cible.libelle} » : seule une colonne de référence de pièce justificative le peut."]
      else
        []
      end
    end
  end

  private

  def erreurs_reference(jsonpath, colonne, opts, cible)
    erreurs = []
    unless colonnes_reference.include?(jsonpath.to_s)
      erreurs << "La colonne « #{colonne} » n’est pas une colonne de référence de pièce justificative d’un référentiel DLNUF."
    end
    if opts['display_usager'] == '1' || opts['display_instructeur'] == '1'
      erreurs << "La colonne « #{colonne} » contient des références de pièces justificatives : elle ne peut pas être affichée."
    end
    if cible && cible.type_champ != TYPE
      erreurs << "La colonne « #{colonne} » ne peut préremplir qu’un champ pièce justificative (« #{cible.libelle} » n’en est pas un)."
    elsif cible && @revision.parent_of(cible) && @revision.parent_of(cible) != @revision.parent_of(@tdc)
      erreurs << "Le champ « #{cible.libelle} » est dans un bloc répétable : il ne peut être prérempli que par un référentiel situé dans la même ligne de ce bloc."
    end
    erreurs
  end

  # cible effective : seulement si le préremplissage est coché (cf. referentiel_mapping_prefillable_with_stable_id)
  def cible_de(opts)
    return nil unless opts['prefill'] == '1' && opts['prefill_stable_id'].present?

    @tdcs[opts['prefill_stable_id'].to_s]
  end

  def colonnes_reference
    @colonnes_reference ||= ReferentielDePolynesie::API.colonnes_reference_pj(@tdc.table_id).map { "$.#{_1}" }
  end
end
