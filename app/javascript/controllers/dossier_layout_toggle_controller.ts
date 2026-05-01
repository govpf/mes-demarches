import { httpRequest } from '@utils';
import { ApplicationController } from './application_controller';

// pf: toggle grille/empilé côté instructeur, sans reload. Progressive enhancement :
// le bouton est rendu `hidden` par HAML et devient visible sur connect() — si JS est
// indisponible, c'est le <noscript> + button_to Rails qui prend le relais.
export class DossierLayoutToggleController extends ApplicationController {
  static targets = ['button', 'liveRegion'];
  static values = {
    urlGrid: String,
    urlStacked: String,
    liveGrid: String,
    liveStacked: String,
    liveError: String,
    labelWhenGrid: String,
    labelWhenStacked: String,
    ariaWhenGrid: String,
    ariaWhenStacked: String
  };

  declare readonly buttonTarget: HTMLButtonElement;
  declare readonly liveRegionTarget: HTMLElement;
  declare readonly urlGridValue: string;
  declare readonly urlStackedValue: string;
  declare readonly liveGridValue: string;
  declare readonly liveStackedValue: string;
  declare readonly liveErrorValue: string;
  declare readonly labelWhenGridValue: string;
  declare readonly labelWhenStackedValue: string;
  declare readonly ariaWhenGridValue: string;
  declare readonly ariaWhenStackedValue: string;

  connect() {
    this.buttonTarget.hidden = false;
  }

  async toggle() {
    const grids = this.grids();
    if (grids.length === 0) return;

    const wasStacked = grids[0].classList.contains('champs-grid--stacked');
    const nextMode: 'grid' | 'stacked' = wasStacked ? 'grid' : 'stacked';
    const nextUrl =
      nextMode === 'grid' ? this.urlGridValue : this.urlStackedValue;

    this.applyMode(nextMode, grids);
    this.liveRegionTarget.textContent =
      nextMode === 'grid' ? this.liveGridValue : this.liveStackedValue;

    try {
      await httpRequest(nextUrl, { method: 'POST' }).json();
    } catch {
      this.applyMode(wasStacked ? 'stacked' : 'grid', grids);
      this.liveRegionTarget.textContent = this.liveErrorValue;
    }
  }

  private grids(): HTMLElement[] {
    return Array.from(document.querySelectorAll<HTMLElement>('.champs-grid'));
  }

  private applyMode(mode: 'grid' | 'stacked', grids: HTMLElement[]) {
    grids.forEach((grid) => {
      grid.classList.toggle('champs-grid--stacked', mode === 'stacked');
    });
    // Le bouton doit refléter le mode courant et proposer l'action inverse.
    this.buttonTarget.setAttribute('aria-pressed', String(mode === 'stacked'));
    this.buttonTarget.setAttribute(
      'aria-label',
      mode === 'grid' ? this.ariaWhenGridValue : this.ariaWhenStackedValue
    );
    this.buttonTarget.textContent =
      mode === 'grid' ? this.labelWhenGridValue : this.labelWhenStackedValue;
    this.buttonTarget.classList.remove(
      'fr-icon-layout-grid-fill',
      'fr-icon-list-unordered'
    );
    this.buttonTarget.classList.add(
      mode === 'grid' ? 'fr-icon-list-unordered' : 'fr-icon-layout-grid-fill'
    );
  }
}
