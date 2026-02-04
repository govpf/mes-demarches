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
    grouped_variables?: {
      metadonnees: Record<string, string>;
      champs_formulaire: Record<string, string>;
      dossiers_lies: Record<string, string>;
    };
  }) {
    const grouped = data.grouped_variables;

    if (!grouped) {
      this.displayError('Aucune variable disponible');
      return;
    }

    const sections = [
      { title: 'Métadonnées', vars: grouped.metadonnees },
      { title: 'Champs du formulaire', vars: grouped.champs_formulaire },
      { title: 'Dossiers liés', vars: grouped.dossiers_lies }
    ];

    const html = sections
      .filter((s) => Object.keys(s.vars).length > 0)
      .map((s) => this.renderSection(s.title, s.vars))
      .join('');

    this.listTarget.innerHTML = html;
  }

  private renderSection(
    title: string,
    variables: Record<string, string>
  ): string {
    const items = Object.entries(variables)
      .map(([key, value]) => {
        const displayValue =
          value === ''
            ? '<em style="color: #999;">(vide)</em>'
            : value.length > 80
              ? this.escapeHtml(value.substring(0, 80)) + '...'
              : this.escapeHtml(value);

        return `<li><strong>${this.escapeHtml(key)}</strong> : ${displayValue}</li>`;
      })
      .join('');

    return `
      <div class="fr-mb-3w">
        <h4 class="fr-h6">${title}</h4>
        <ul class="fr-text--xs" style="list-style: none; padding: 0;">${items}</ul>
      </div>
    `;
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
