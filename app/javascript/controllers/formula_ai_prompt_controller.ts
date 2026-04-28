import { ApplicationController } from './application_controller';

/**
 * FormulaAiPromptController
 *
 * Copies an auto-generated formula-writing prompt to the clipboard so the
 * administrator can paste it into the AI of their choice. Provides short
 * inline visual feedback on the button after a successful copy.
 *
 * @example
 * ```haml
 * .cell{ data: {
 *   controller: 'formula-ai-prompt',
 *   formula_ai_prompt_prompt_value: prompt_text
 * }}
 *   %button{ data: { formula_ai_prompt_target: 'button', action: 'click->formula-ai-prompt#copy' } }
 *     Copier une documentation pour mon IA
 * ```
 */
export class FormulaAiPromptController extends ApplicationController {
  static targets = ['button'];
  static values = { prompt: String };

  declare readonly buttonTarget: HTMLButtonElement;
  declare readonly hasButtonTarget: boolean;
  declare readonly promptValue: string;

  private originalButtonHTML: string | null = null;
  private resetTimer: number | null = null;

  async copy(event: Event): Promise<void> {
    event.preventDefault();

    if (!this.promptValue) {
      this.flashFeedback('Documentation indisponible', false);
      return;
    }

    if (!navigator.clipboard) {
      this.flashFeedback('Presse-papier non disponible', false);
      return;
    }

    try {
      await navigator.clipboard.writeText(this.promptValue);
      this.flashFeedback('Documentation copiée', true);
    } catch {
      this.flashFeedback('Échec de la copie', false);
    }
  }

  private flashFeedback(message: string, success: boolean): void {
    if (!this.hasButtonTarget) return;

    const button = this.buttonTarget;

    if (this.originalButtonHTML === null) {
      this.originalButtonHTML = button.innerHTML;
    }

    if (this.resetTimer !== null) {
      window.clearTimeout(this.resetTimer);
    }

    button.innerHTML = message;
    button.classList.remove('fr-icon-clipboard-line');
    button.classList.add(success ? 'fr-icon-check-line' : 'fr-icon-error-line');

    this.resetTimer = window.setTimeout(() => {
      if (this.originalButtonHTML !== null) {
        button.innerHTML = this.originalButtonHTML;
      }
      button.classList.remove('fr-icon-check-line', 'fr-icon-error-line');
      button.classList.add('fr-icon-clipboard-line');
      this.resetTimer = null;
    }, 2500);
  }
}
