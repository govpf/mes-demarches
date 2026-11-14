# frozen_string_literal: true

# pf: DLNUF — analyse du marqueur « mes-demarches: » posé par le schema builder dans la
# description d'une colonne Baserow (contrat docs/superpowers/specs/2026-11-06-contrat-referentiel-dlnuf.md §3.2).
# Retourne nil (aucune ligne marqueur), :invalid (marqueur illisible : les appelants refusent,
# jamais de repli en catalogue) ou un Hash { 'cle' => 'valeur' } (clés en minuscules).
class ReferentielDePolynesie::Marqueur
  CONTRATS_CONNUS = ['1'].freeze
  # pf: une ligne qui ressemble à un marqueur (même mal écrite) est candidate ; seule la forme
  # exacte « mes-demarches: » est valide. Une faute de frappe doit refuser, pas désactiver.
  # Variantes couvertes : accent (« démarches »), espace ou souligné, singulier.
  CANDIDAT = /\A\s*mes[\s_-]*d[eéÉ]marches?\s*:/i
  PREFIXE = /\A\s*mes-demarches:/i

  def self.parse(texte)
    candidates = texte.to_s.each_line.grep(CANDIDAT)
    return nil if candidates.empty?
    return :invalid if candidates.size > 1

    ligne = candidates.first
    return :invalid unless ligne.match?(PREFIXE)

    paires = ligne.sub(PREFIXE, '').split(';').map(&:strip).reject(&:empty?)
    return :invalid if paires.empty?

    resultat = {}
    paires.each do |paire|
      cle, separateur, valeur = paire.partition('=')
      cle = cle.strip.downcase
      return :invalid if separateur.empty? || cle.empty? || resultat.key?(cle) # pf: clé répétée = ambiguë

      resultat[cle] = valeur.strip
    end

    return :invalid if resultat.key?('contrat') && !resultat['contrat'].in?(CONTRATS_CONNUS)

    resultat
  end
end
