import { hide, httpRequest, show } from '@utils';
import { ApplicationController } from './application_controller';

type CheckEmailResponse =
  | {
      success: true;
      suggestions?: string[];
    }
  | { success: false };

export class EmailInputController extends ApplicationController {
  static targets = ['ariaRegion', 'suggestion', 'input'];

  static values = {
    url: String
  };

  declare readonly urlValue: string;

  declare readonly ariaRegionTarget: HTMLElement;
  declare readonly suggestionTarget: HTMLElement;
  declare readonly inputTarget: HTMLInputElement;

  async checkEmail() {
    const email = this.inputTarget.value;

    if (!email || email.length < 5 || !email.includes('@')) {
      return;
    }

    if (email.toLowerCase().endsWith('@gmail.pf')) {
      const address = email.substring(0, email.indexOf('@')) + '@gmail.com';
      this.suggestionTarget.innerHTML = address;
      show(this.ariaRegionTarget);
      this.ariaRegionTarget.focus();
    } else if (email.toLowerCase().endsWith('.pf')) {
      this.discard();
    } else {
      const url = new URL(this.urlValue, document.baseURI);
      url.searchParams.append('email', this.inputTarget.value);

      const data = await httpRequest(url.toString(), { method: 'POST' })
        .json<CheckEmailResponse>()
        .catch(() => null);

      if (data?.success) {
        const suggestion = data.suggestions?.[0];
        if (suggestion) {
          this.suggestionTarget.innerHTML = suggestion;
          show(this.ariaRegionTarget);
          this.ariaRegionTarget.focus();
        }
      }
    }
  }

  accept() {
    hide(this.ariaRegionTarget);
    this.inputTarget.value = this.suggestionTarget.innerHTML;
    this.suggestionTarget.innerHTML = '';
    const nextTarget = document.querySelector<HTMLElement>(
      '[data-email-input-target="next"]'
    );
    if (nextTarget) {
      nextTarget.focus();
    }
  }

  discard() {
    hide(this.ariaRegionTarget);
    this.suggestionTarget.innerHTML = '';
    const nextTarget = document.querySelector<HTMLElement>(
      '[data-email-input-target="next"]'
    );
    if (nextTarget) {
      nextTarget.focus();
    }
  }
}
