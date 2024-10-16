import 'core-js/proposals/relative-indexing-method';
import Rails from '@rails/ujs';
import * as ActiveStorage from '@rails/activestorage';
import * as Turbo from '@hotwired/turbo';
import { Application } from '@hotwired/stimulus';
import '@gouvfr/dsfr/dist/dsfr.module.js';

import '../shared/activestorage/ujs';
import '../shared/safari-11-empty-file-workaround';
import '../shared/toggle-target';

import { registerControllers } from '../shared/stimulus-loader';

import '../new_design/form-validation';

import '../new_design/champs/te_fenua';

import { toggleCondidentielExplanation } from '../new_design/avis';
import {
  showMotivation,
  motivationCancel,
  showImportJustificatif,
  showDeleteJustificatif,
  deleteJustificatif
} from '../new_design/instruction-button';
import { showFusion, showNewAccount } from '../new_design/fc-fusion';

const application = Application.start();
registerControllers(application);

// This is the global application namespace where we expose helpers used from rails views
const DS = {
  toggleCondidentielExplanation,
  showMotivation,
  motivationCancel,
  showImportJustificatif,
  showDeleteJustificatif,
  deleteJustificatif,
  showFusion,
  showNewAccount
};

// Start Rails helpers
ActiveStorage.start();
if (!window._rails_loaded) {
  Rails.start();
}
Turbo.session.drive = false;

// Expose globals
window.DS = window.DS || DS;

import('../shared/track/matomo');
import('../shared/track/sentry');
