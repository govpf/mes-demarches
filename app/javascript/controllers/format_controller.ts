import { ApplicationController } from './application_controller';
import { formatIdentifiantEntreprise } from '../shared/identifiant-entreprise';

export class FormatController extends ApplicationController {
  connect() {
    const format = this.element.getAttribute('data-format');
    switch (format) {
      case 'deleteSpace':
        this.on('change', (event) => {
          const target = event.target as HTMLInputElement;
          const value = this.deleteSpace(target.value);
          replaceValue(target, value);
        });
        break;
      case 'list':
        this.on('change', (event) => {
          const target = event.target as HTMLInputElement;
          const value = this.formatList(target.value);
          replaceValue(target, value);
        });
        break;
      case 'siret': {
        // Format immediately on connect if field has a value
        const input = this.element as HTMLInputElement;
        if (input.value) {
          const value = this.formatSIRET(input.value);
          replaceValue(input, value);
        }

        this.on('input', (event) => {
          const target = event.target as HTMLInputElement;
          const value = this.formatSIRET(target.value);
          replaceValue(target, value);
        });
        break;
      }
      case 'iban':
        this.on('input', (event) => {
          const target = event.target as HTMLInputElement;
          const value = this.formatIBAN(target.value);
          replaceValue(target, value);
        });
        break;
      case 'integer':
        this.on('input', (event) => {
          const target = event.target as HTMLInputElement;
          const value = this.formatInteger(target.value);
          replaceValue(target, value);
        });
        break;
      case 'decimal':
        this.on('input', (event) => {
          const target = event.target as HTMLInputElement;
          const value = this.formatDecimal(target.value);
          replaceValue(target, value);
        });
        break;
    }
  }
  private deleteSpace(value: string) {
    return value.replace(/\s*/g, '');
  }

  private formatList(value: string) {
    return value.replace(/;/g, ',');
  }

  private formatSIRET(value: string) {
    // pf: règles centralisées dans shared/identifiant-entreprise.ts, miroir du
    // value object IdentifiantEntreprise côté serveur
    return formatIdentifiantEntreprise(value);
  }

  private formatIBAN(value: string) {
    return value
      .replace(/[^\dA-Z]/gi, '')
      .replace(/(.{4})/g, '$1 ')
      .trim()
      .toUpperCase();
  }

  private formatInteger(value: string) {
    return value.replace(/[^-?\d]/g, '');
  }

  private formatDecimal(value: string) {
    let formattedNumber = value;
    const lastDotIndex = value.lastIndexOf('.');
    const lastCommaIndex = value.lastIndexOf(',');
    if (lastDotIndex != -1 && lastCommaIndex != -1) {
      if (lastDotIndex < lastCommaIndex) {
        formattedNumber = value.replace(/\./g, '');
      } else {
        formattedNumber = value.replace(/,/g, '');
      }
    }
    return formattedNumber
      .replace(/,/g, '.')
      .replace(new RegExp(`[^-?\\d.]`, 'g'), '');
  }
}

function replaceValue(target: HTMLInputElement, value: string) {
  const delta = target.value.length - value.length;
  const start = target.selectionStart;
  const end = target.selectionStart;
  const dir = target.selectionDirection;
  target.value = value;
  target.selectionStart = start ? start - delta : 0;
  target.selectionEnd = end ? end - delta : 0;
  target.selectionDirection = dir;
}
