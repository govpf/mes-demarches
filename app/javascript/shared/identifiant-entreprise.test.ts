import { suite, test, expect } from 'vitest';

import { formatIdentifiantEntreprise } from './identifiant-entreprise';

// Ce fichier vérifie que la mise en forme à la frappe reste alignée sur la
// validation serveur (app/models/identifiant_entreprise.rb#format_lisible),
// et épingle explicitement les deux divergences volontaires entre les deux
// implémentations : le garde-fou anti-ambiguïté propre à la frappe en cours,
// et l'absence de vérification de la clé de Luhn côté JavaScript.
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

  test('numéro purement numérique de 13 chiffres : rendu tel quel, saisie en cours', () => {
    expect(formatIdentifiantEntreprise('1234567890123')).toEqual(
      '1234567890123'
    );
  });

  test('chaîne vide', () => {
    expect(formatIdentifiantEntreprise('')).toEqual('');
  });

  // Divergence volontaire n°1 avec le Ruby, documentée en tête du module :
  // IdentifiantEntreprise#siret? vérifie la clé de Luhn avant de considérer
  // la valeur comme un SIRET ; #format_lisible ne groupe donc PAS un SIRET à
  // clé fausse. Ce module JS, lui, groupe sur la seule forme (14 chiffres),
  // sans vérifier Luhn. Pendant la frappe, l'utilisateur passe forcément par
  // des états où la clé est temporairement fausse ; dégrouper l'affichage à
  // cet instant serait déroutant, et c'est au serveur de refuser la valeur
  // avec un message de checksum. Ne pas « rétablir la symétrie » ici : c'est
  // un choix, pas un oubli.
  test('SIRET à clé de Luhn fausse : groupé quand même en JS (divergence volontaire avec le Ruby)', () => {
    expect(formatIdentifiantEntreprise('41816609600052')).toEqual(
      '418 166 096 00052'
    );
  });

  suite(
    'valeur complète (enCoursDeSaisie: false, valeur par défaut) — ex. rendue par le serveur au chargement',
    () => {
      test('numéro Tahiti partiel purement numérique à 7 chiffres : tiret posé', () => {
        expect(formatIdentifiantEntreprise('0022530')).toEqual('002253-0');
      });

      test('numéro Tahiti partiel purement numérique à 8 chiffres : tiret posé', () => {
        expect(formatIdentifiantEntreprise('00225300')).toEqual('002253-00');
      });

      // pf: cas réel signalé en relecture — 002253001 est un numéro Tahiti qui
      // existe. Le serveur rend le champ déjà mis en forme ("002253-001", via
      // pretty_siret) ; sans ce test, formatIdentifiantEntreprise appelé au
      // chargement de la page (connect()) défaisait cette mise en forme.
      test('numéro Tahiti complet purement numérique à 9 chiffres : tiret posé, pas de régression sur la valeur déjà formatée par le serveur', () => {
        expect(formatIdentifiantEntreprise('002253001')).toEqual('002253-001');
        expect(formatIdentifiantEntreprise('002253-001')).toEqual('002253-001');
      });
    }
  );

  suite('frappe en cours (enCoursDeSaisie: true) — événement `input`', () => {
    // pf: point de conception à ne pas « corriger ». Un numéro purement
    // numérique de 7, 8 ou 9 chiffres est indiscernable, pendant la frappe,
    // des premiers chiffres d'un SIRET en cours de saisie. Poser un tiret ici
    // ferait apparaître puis disparaître l'affichage au caractère suivant.
    // On accepte donc qu'un numéro Tahiti purement numérique (ex. 002253001,
    // qui existe réellement) ne reçoive pas son tiret à la frappe : la valeur
    // est normalisée côté serveur de toute façon, et l'ambiguïté est réelle
    // et non résoluble côté client seul.
    test('numéro purement numérique de 7 chiffres : pas de tiret pendant la frappe', () => {
      expect(
        formatIdentifiantEntreprise('0022530', { enCoursDeSaisie: true })
      ).toEqual('0022530');
    });

    test('numéro purement numérique de 8 chiffres : pas de tiret pendant la frappe', () => {
      expect(
        formatIdentifiantEntreprise('00225300', { enCoursDeSaisie: true })
      ).toEqual('00225300');
    });

    test('numéro purement numérique de 9 chiffres : pas de tiret (ambiguïté avec un SIRET en cours de frappe)', () => {
      expect(
        formatIdentifiantEntreprise('123456789', { enCoursDeSaisie: true })
      ).toEqual('123456789');
    });

    test('un numéro Tahiti commençant par une lettre reçoit son tiret même pendant la frappe (pas d’ambiguïté possible avec un SIRET)', () => {
      expect(
        formatIdentifiantEntreprise('G339720', { enCoursDeSaisie: true })
      ).toEqual('G33972-0');
    });
  });
});
