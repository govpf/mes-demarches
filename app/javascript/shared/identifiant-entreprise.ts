// pf: miroir TypeScript de app/models/identifiant_entreprise.rb.
// Toute modification des règles doit être répercutée des deux côtés — la mise
// en forme à la frappe doit suivre exactement la validation serveur.
const TAHITI_PARTIEL = /^[0-9A-Z]\d{5,7}$/; // 6 à 8 caractères
const TAHITI_COMPLET = /^[0-9A-Z]\d{8}$/; // 9 caractères
const SIRET = /^\d{14}$/; // 14 chiffres

/** Retire espaces et tirets, met en capitales. */
function normalise(value: string): string {
  return value.replace(/[\s-]/g, '').toUpperCase();
}

/**
 * Met en forme un identifiant d'entreprise selon son référentiel :
 * - SIRET complet     : "418 166 096 00051"
 * - Tahiti 7 à 9 car. : "G33972-001"
 * - tout le reste     : rendu tel quel, la saisie est en cours
 */
export function formatIdentifiantEntreprise(value: string): string {
  const brut = normalise(value);

  if (SIRET.test(brut)) {
    return `${brut.slice(0, 3)} ${brut.slice(3, 6)} ${brut.slice(6, 9)} ${brut.slice(9)}`;
  }
  // Un numéro de 9 chiffres est ambigu pendant la frappe : ce peut être un
  // numéro Tahiti complet ou les 9 premiers chiffres d'un SIRET. On n'insère le
  // tiret que si la valeur ne peut pas devenir un SIRET, c'est-à-dire si elle
  // commence par une lettre.
  const peutDevenirSiret = /^\d+$/.test(brut) && brut.length < 14;
  if (
    !peutDevenirSiret &&
    (TAHITI_COMPLET.test(brut) || TAHITI_PARTIEL.test(brut)) &&
    brut.length > 6
  ) {
    return `${brut.slice(0, 6)}-${brut.slice(6)}`;
  }
  return brut;
}
