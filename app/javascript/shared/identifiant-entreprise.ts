// pf: miroir TypeScript de app/models/identifiant_entreprise.rb.
// Toute modification des règles doit être répercutée des deux côtés — la mise
// en forme à la frappe doit suivre exactement la validation serveur.
//
// Deux contextes d'appel, avec un garde-fou différent selon le cas :
// - `enCoursDeSaisie: true` (événement `input`, l'utilisateur tape) : la
//   valeur est potentiellement incomplète, et un numéro purement numérique
//   de 9 chiffres est ambigu (voir plus bas) — pas de tiret dans ce cas.
// - `enCoursDeSaisie: false`, valeur par défaut (valeur déjà complète, ex.
//   rendue par le serveur via `pretty_siret` au chargement de la page,
//   cf. `app/components/editable_champ/siret_component/siret_component.html.haml`) :
//   aucune ambiguïté possible, la mise en forme s'applique pleinement, y
//   compris sur un numéro Tahiti purement numérique — "002253001" existe
//   réellement et doit devenir "002253-001" au chargement.
//
// Autre divergence volontaire avec le Ruby : contrairement à
// `IdentifiantEntreprise#siret?`, ce module ne vérifie jamais la clé de Luhn
// avant de grouper un SIRET en tranches de 3/3/3/5. Un SIRET affichant une
// clé fausse (ex. "41816609600052") est donc quand même groupé ici. C'est
// voulu : pendant la frappe, l'utilisateur passe forcément par des états où
// la clé est temporairement fausse, et dégrouper l'affichage à cet instant
// serait déroutant. La validation de la clé — et le refus avec un message de
// checksum — reste entièrement du côté serveur ; ce module ne fait que de la
// présentation visuelle.
const TAHITI_PARTIEL = /^[0-9A-Z]\d{5,7}$/; // 6 à 8 caractères
const TAHITI_COMPLET = /^[0-9A-Z]\d{8}$/; // 9 caractères
const SIRET = /^\d{14}$/; // 14 chiffres

/** Retire espaces et tirets, met en capitales. */
function normalise(value: string): string {
  return value.replace(/[\s-]/g, '').toUpperCase();
}

interface FormatIdentifiantEntrepriseOptions {
  /**
   * true pendant la frappe (événement `input`) : un numéro purement
   * numérique de 9 chiffres est alors indiscernable des 9 premiers chiffres
   * d'un SIRET en cours de saisie, donc pas de tiret posé. false (défaut)
   * pour une valeur déjà complète (ex. valeur initiale rendue par le
   * serveur) : aucune ambiguïté, le tiret est posé même sur un Tahiti
   * purement numérique.
   */
  enCoursDeSaisie?: boolean;
}

/**
 * Met en forme un identifiant d'entreprise selon son référentiel :
 * - SIRET complet     : "418 166 096 00051"
 * - Tahiti 7 à 9 car. : "G33972-001"
 * - tout le reste     : rendu tel quel, la saisie est en cours
 */
export function formatIdentifiantEntreprise(
  value: string,
  { enCoursDeSaisie = false }: FormatIdentifiantEntrepriseOptions = {}
): string {
  const brut = normalise(value);

  if (SIRET.test(brut)) {
    return `${brut.slice(0, 3)} ${brut.slice(3, 6)} ${brut.slice(6, 9)} ${brut.slice(9)}`;
  }
  // Un numéro de 9 chiffres est ambigu pendant la frappe : ce peut être un
  // numéro Tahiti complet ou les 9 premiers chiffres d'un SIRET en cours de
  // saisie. On n'insère le tiret que si la valeur ne peut pas devenir un
  // SIRET, c'est-à-dire si elle commence par une lettre — et seulement
  // pendant la frappe (`enCoursDeSaisie`) : une valeur déjà complète n'a pas
  // cette ambiguïté et reçoit toujours sa mise en forme pleine.
  const peutDevenirSiret =
    enCoursDeSaisie && /^\d+$/.test(brut) && brut.length < 14;
  if (
    !peutDevenirSiret &&
    (TAHITI_COMPLET.test(brut) || TAHITI_PARTIEL.test(brut)) &&
    brut.length > 6
  ) {
    return `${brut.slice(0, 6)}-${brut.slice(6)}`;
  }
  return brut;
}
