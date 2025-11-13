// pf: Contrôleur pour prévisualiser les variables qui seront envoyées à Lexpol
import { ApplicationController } from './application_controller';

export class LexpolPreviewController extends ApplicationController {
  static targets = ['list', 'container'];

  declare readonly listTarget: HTMLElement;
  declare readonly containerTarget: HTMLElement;

  #loaded = false;

  async toggle(event: Event) {
    event.preventDefault();

    const button = event.currentTarget as HTMLElement;
    const isHidden = this.containerTarget.classList.contains('hidden');

    if (isHidden) {
      // Afficher le container
      this.containerTarget.classList.remove('hidden');
      button.innerText = 'Masquer les variables disponibles';

      // Charger les variables si pas encore chargées
      if (!this.#loaded) {
        await this.loadVariables();
      }
    } else {
      // Masquer le container
      this.containerTarget.classList.add('hidden');
      button.innerText = 'Afficher les variables disponibles';
    }
  }

  async loadVariables() {
    const url = this.containerTarget.dataset.url;

    if (!url) {
      this.displayError('URL non configurée');
      return;
    }

    try {
      const response = await fetch(url, {
        headers: {
          Accept: 'application/json'
        }
      });

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }

      const data = await response.json();

      if (data.error) {
        this.displayError(data.error);
      } else {
        this.displayGroupedVariables(data);
        this.#loaded = true;
      }
    } catch (error) {
      console.error('Error loading variables:', error);
      this.displayError('Impossible de charger les variables');
    }
  }

  private displayGroupedVariables(data: {
    variables?: Record<string, string>;
    linked_dossiers?: Array<{ libelle: string; suffixe: string }>;
  }) {
    const allVars = data.variables || {};
    const linkedDossiers = data.linked_dossiers || [];

    // Grouper les variables
    const groups: Record<string, string[]> = { main: [] };
    const suffixes = linkedDossiers.map((d) => d.suffixe);

    Object.keys(allVars).forEach((key) => {
      let grouped = false;
      for (const suffix of suffixes) {
        if (key.endsWith(` (${suffix})`)) {
          if (!groups[suffix]) groups[suffix] = [];
          groups[suffix].push(key);
          grouped = true;
          break;
        }
      }
      if (!grouped) groups.main.push(key);
    });

    // Afficher
    let html = '';

    // Dossier principal
    if (groups.main.length > 0) {
      html +=
        '<div class="fr-mb-3w"><h4 class="fr-h6">📂 Dossier principal</h4><ul class="fr-text--xs" style="list-style: none; padding: 0;">';
      groups.main.forEach((key) => {
        const value = allVars[key] || '(vide)';
        const displayValue =
          value.length > 80 ? value.substring(0, 80) + '...' : value;
        html += `<li style="margin-bottom: 0.5rem;"><strong>${this.escapeHtml(key)}</strong> : ${this.escapeHtml(displayValue)}</li>`;
      });
      html += '</ul></div>';
    }

    // Dossiers liés
    linkedDossiers.forEach((dossier) => {
      const suffix = dossier.suffixe;
      html += `<div class="fr-mb-3w"><h4 class="fr-h6">📎 ${this.escapeHtml(dossier.libelle)} <span class="fr-badge fr-badge--sm fr-badge--info">${this.escapeHtml(suffix)}</span></h4>`;
      if (groups[suffix] && groups[suffix].length > 0) {
        html +=
          '<ul class="fr-text--xs" style="list-style: none; padding: 0;">';
        groups[suffix].forEach((key) => {
          const value = allVars[key] || '(vide)';
          const displayValue =
            value.length > 80 ? value.substring(0, 80) + '...' : value;
          html += `<li style="margin-bottom: 0.5rem;"><strong>${this.escapeHtml(key)}</strong> : ${this.escapeHtml(displayValue)}</li>`;
        });
        html += '</ul>';
      } else {
        html +=
          '<p class="fr-text--xs">Aucune donnée disponible pour ce dossier</p>';
      }
      html += '</div>';
    });

    this.listTarget.innerHTML = html;
  }

  private displayError(message: string) {
    this.listTarget.innerHTML = `
      <div class="fr-alert fr-alert--error">
        <p>${this.escapeHtml(message)}</p>
      </div>
    `;
  }

  private escapeHtml(text: string): string {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
}
