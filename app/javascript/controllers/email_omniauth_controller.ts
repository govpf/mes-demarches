import { ApplicationController } from './application_controller';

export class EmailOmniauthController extends ApplicationController {
  static targets = [
    'useProviderEmail',
    'emailField',
    'submit',
    'emailInput',
    'form'
  ];

  emailFieldTarget!: HTMLElement;
  useProviderEmailTargets!: HTMLInputElement[];
  submitTarget!: HTMLButtonElement;
  emailInputTarget!: HTMLInputElement;
  formTarget!: HTMLFormElement;

  providerEmailPathValue!: string;
  customEmailPathValue!: string;

  static values = {
    providerEmailPath: String,
    customEmailPath: String
  };

  triggerEmailField() {
    if (this.useProviderEmail()) {
      this.emailFieldTarget.classList.add('hidden');
      this.emailFieldTarget.setAttribute('aria-hidden', 'true');

      this.emailInputTarget.removeAttribute('required');
      this.emailInputTarget.value = '';

      this.formTarget.action = this.providerEmailPathValue;
    } else {
      this.emailFieldTarget.classList.remove('hidden');
      this.emailFieldTarget.setAttribute('aria-hidden', 'false');

      this.emailInputTarget.setAttribute('required', '');

      this.formTarget.action = this.customEmailPathValue;
    }
  }

  triggerSubmitDisabled() {
    if (this.useProviderEmail() || this.isEmailInputFilled()) {
      this.submitTarget.disabled = false;
    } else {
      this.submitTarget.disabled = true;
    }
  }

  useProviderEmail() {
    return (
      this.useProviderEmailTargets.find((target) => target.checked)?.value ===
        'true' || false
    );
  }

  isEmailInputFilled() {
    return this.emailInputTarget.value.length > 0;
  }
}
