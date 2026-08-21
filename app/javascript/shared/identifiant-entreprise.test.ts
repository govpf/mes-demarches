import { suite, test, expect } from 'vitest';

import { formatIdentifiantEntreprise } from './identifiant-entreprise';

// Miroir de la table de vérité de spec/models/identifiant_entreprise_spec.rb
// (côté Ruby) — toute divergence entre les deux tables signale un désaccord
// entre la mise en forme à la frappe et la validation serveur.
suite('formatIdentifiantEntreprise', () => {
  test('numéro Tahiti partiel à 6 caractères : pas de tiret', () => {
    expect(formatIdentifiantEntreprise('G33972')).toEqual('G33972');
  });

  test('numéro Tahiti partiel à 7 caractères', () => {
    expect(formatIdentifiantEntreprise('G339720')).toEqual('G33972-0');
  });

  test('numéro Tahiti complet à 9 caractères', () => {
    expect(formatIdentifiantEntreprise('G33972001')).toEqual('G33972-001');
  });

  test('normalisation de la casse et du tiret déjà présent', () => {
    expect(formatIdentifiantEntreprise('g33972-001')).toEqual('G33972-001');
  });

  test('les espaces sont retirés avant mise en forme', () => {
    expect(formatIdentifiantEntreprise(' G33972 001 ')).toEqual('G33972-001');
  });

  test('SIRET complet à 14 chiffres', () => {
    expect(formatIdentifiantEntreprise('41816609600051')).toEqual(
      '418 166 096 00051'
    );
  });

  test('SIRET déjà mis en forme : idempotent', () => {
    expect(formatIdentifiantEntreprise('418 166 096 00051')).toEqual(
      '418 166 096 00051'
    );
  });

  // pf: point de conception à ne pas « corriger ». Un numéro purement
  // numérique de 9 chiffres est indiscernable, pendant la frappe, des 9
  // premiers chiffres d'un SIRET en cours de saisie. Poser un tiret ici
  // ferait apparaître puis disparaître l'affichage au caractère suivant
  // (10e chiffre). On accepte donc qu'un numéro Tahiti purement numérique
  // (ex. 002253001, qui existe réellement) ne reçoive pas son tiret à la
  // frappe : la valeur est normalisée côté serveur de toute façon, et
  // l'ambiguïté est réelle et non résoluble côté client seul.
  test('numéro purement numérique de 9 chiffres : pas de tiret (ambiguïté avec un SIRET en cours de frappe)', () => {
    expect(formatIdentifiantEntreprise('123456789')).toEqual('123456789');
  });

  test('numéro purement numérique de 13 chiffres : rendu tel quel, saisie en cours', () => {
    expect(formatIdentifiantEntreprise('1234567890123')).toEqual(
      '1234567890123'
    );
  });

  test('chaîne vide', () => {
    expect(formatIdentifiantEntreprise('')).toEqual('');
  });
});
