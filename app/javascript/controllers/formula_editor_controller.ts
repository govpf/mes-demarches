import { ApplicationController } from './application_controller';

interface ColumnReference {
  id: string; // "tdc456" or "dossier_number"
  label: string; // "Montant HT" or "Numéro du dossier"
  type: string; // "integer", "text", "date", etc.
  category: string; // "type_de_champ", "self", "user", etc.
  paths?: Array<{
    // Sub-properties (for DN, referentiel, etc.)
    path: string; // "date_de_naissance", "commune", etc.
    label: string; // "Date de naissance", "Commune"
  }>;
}

// Backward compatibility interface
interface ChampReference {
  label: string;
  stable_id: number;
}

export class FormulaEditorController extends ApplicationController {
  static targets = ['userExpression', 'stableExpression', 'validationMessage'];

  declare readonly userExpressionTarget: HTMLTextAreaElement;
  declare readonly stableExpressionTarget: HTMLInputElement;
  declare readonly validationMessageTarget: HTMLElement;

  declare readonly hasValidationMessageTarget: boolean;

  // Available columns passed as JSON in data-formula-editor-available-columns-value
  static values = {
    availableColumns: Array, // New: ColumnReference[]
    champs: Array, // Deprecated: for backward compatibility
    debounceDelay: { type: Number, default: 300 }
  };

  declare readonly availableColumnsValue: ColumnReference[];
  declare readonly champsValue: ChampReference[]; // Deprecated
  declare readonly debounceDelayValue: number;
  declare readonly hasAvailableColumnsValue: boolean;

  private debounceTimer: number | null = null;

  connect() {
    // If we have an initial stable expression but empty user expression,
    // convert column_ids back to labels for display
    if (this.stableExpressionTarget.value && !this.userExpressionTarget.value) {
      this.userExpressionTarget.value = this.convertToLabels(
        this.stableExpressionTarget.value
      );
    }
    // Don't validate on connect to avoid showing duplicate errors after server morph
    // Validation will happen on user input via onInput()

    // Listen for insertions from autocomplete (auto-cleanup via ApplicationController.on)
    this.on('formula-autocomplete:insert', () => {
      // Cancel any pending debounce
      if (this.debounceTimer) {
        clearTimeout(this.debounceTimer);
      }
      // Validate immediately
      this.convertExpression();
    });
  }

  private convertToLabels(expression: string): string {
    // Support both new column format and old stable_id format
    if (
      this.hasAvailableColumnsValue &&
      this.availableColumnsValue.length > 0
    ) {
      return this.convertColumnIdsToLabels(expression);
    } else {
      return this.convertStableIdsToLabels(expression);
    }
  }

  private convertStableIdsToLabels(stableExpression: string): string {
    // Backward compatibility: convert {456} to {Label}
    const champsMap = new Map<number, string>();

    // Build a map of stable_id -> label
    this.champsValue.forEach((champ) => {
      champsMap.set(champ.stable_id, champ.label);
    });

    // Replace {stable_id} with {Label}
    return stableExpression.replace(/\{(\d+)\}/g, (match, stableId) => {
      const id = parseInt(stableId, 10);
      const label = champsMap.get(id);

      if (label !== undefined) {
        return `{${label}}`;
      } else {
        return match; // Keep original if not found
      }
    });
  }

  private convertColumnIdsToLabels(expression: string): string {
    // New: convert {tdc456}, {dossier_number}, {tdc456/date_de_naissance} to {Label}
    const columnsMap = new Map<string, string>();

    // Build a map of column_id -> label
    this.availableColumnsValue.forEach((column) => {
      columnsMap.set(column.id, column.label);

      // Also add sub-properties if they exist
      if (column.paths) {
        column.paths.forEach((path) => {
          columnsMap.set(`${column.id}/${path.path}`, path.label);
        });
      }
    });

    // Replace {column_id} or {column_id/path} with {Label}
    return expression.replace(/\{([^}]+)\}/g, (match, columnId) => {
      const label = columnsMap.get(columnId.trim());

      if (label !== undefined) {
        return `{${label}}`;
      } else {
        return match; // Keep original if not found
      }
    });
  }

  onInput() {
    // Debounce conversion to avoid too many updates
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }

    this.debounceTimer = window.setTimeout(() => {
      this.convertExpression();
    }, this.debounceDelayValue);
  }

  private convertExpression() {
    const userExpression = this.userExpressionTarget.value;

    if (!userExpression) {
      this.stableExpressionTarget.value = '';
      this.clearValidation();
      // Clear any custom validity
      this.userExpressionTarget.setCustomValidity('');
      return;
    }

    try {
      let expression;
      if (
        this.hasAvailableColumnsValue &&
        this.availableColumnsValue.length > 0
      ) {
        expression = this.convertToColumnIds(userExpression);
      } else {
        expression = this.convertToStableIds(userExpression);
      }
      this.stableExpressionTarget.value = expression;
      this.showValidation('', 'success');
      // Clear any custom validity
      this.userExpressionTarget.setCustomValidity('');
    } catch (error) {
      // Keep the original expression with unresolved variables
      // Server-side validation will catch and report them
      this.stableExpressionTarget.value = userExpression;
      const message =
        error instanceof Error ? error.message : 'Erreur de validation';
      this.showValidation(message, 'error');
      // Note: setCustomValidity doesn't block AJAX saves, only form submissions
    }
  }

  private convertToStableIds(expression: string): string {
    // Backward compatibility: convert {Label} to {stable_id}
    const champsMap = new Map<string, number>();

    // Build a map of label -> stable_id
    this.champsValue.forEach((champ) => {
      // Normalize labels for case-insensitive matching
      const normalizedLabel = champ.label.trim().toLowerCase();
      champsMap.set(normalizedLabel, champ.stable_id);
    });

    // Replace {Label} with {stable_id}
    return expression.replace(/\{([^}]+)\}/g, (match, label) => {
      const normalizedLabel = label.trim().toLowerCase();
      const stableId = champsMap.get(normalizedLabel);

      if (stableId !== undefined) {
        return `{${stableId}}`;
      } else {
        // If not found, check if it's already a stable_id
        if (/^\d+$/.test(label.trim())) {
          return match; // Already a stable_id
        }
        throw new Error(
          `Champ "${label}" : doit précéder la formule ou n'existe pas`
        );
      }
    });
  }

  private convertToColumnIds(expression: string): string {
    // New: convert {Label} to {tdc456}, {dossier_number}, or {tdc456/path}
    const columnsMapById = new Map<string, ColumnReference>();
    const columnsMapByLabel = new Map<string, string>(); // label -> column_id

    // Build maps
    this.availableColumnsValue.forEach((column) => {
      columnsMapById.set(column.id, column);
      const normalizedLabel = column.label.trim().toLowerCase();
      columnsMapByLabel.set(normalizedLabel, column.id);

      // Also add sub-properties
      if (column.paths) {
        column.paths.forEach((path) => {
          const fullId = `${column.id}/${path.path}`;
          const pathNormalizedLabel = path.label.trim().toLowerCase();
          columnsMapByLabel.set(pathNormalizedLabel, fullId);
        });
      }
    });

    // Replace {Label} with {column_id}
    return expression.replace(/\{([^}]+)\}/g, (match, label) => {
      const normalizedLabel = label.trim().toLowerCase();
      const columnId = columnsMapByLabel.get(normalizedLabel);

      if (columnId !== undefined) {
        return `{${columnId}}`;
      } else {
        // Check if it's already a column_id
        if (/^(tdc\d+|dossier_|individual_|entreprise_)/.test(label.trim())) {
          return match; // Already a column_id
        }
        throw new Error(
          `Colonne "${label}" : doit précéder la formule ou n'existe pas`
        );
      }
    });
  }

  private showValidation(message: string, type: 'success' | 'error') {
    if (!this.hasValidationMessageTarget) return;

    if (message) {
      this.validationMessageTarget.textContent = message;
      this.validationMessageTarget.className =
        type === 'error'
          ? 'fr-message fr-message--error'
          : 'fr-message fr-message--valid';
      this.validationMessageTarget.style.display = 'block';
    } else {
      this.clearValidation();
    }
  }

  private clearValidation() {
    if (!this.hasValidationMessageTarget) return;

    this.validationMessageTarget.textContent = '';
    this.validationMessageTarget.className = 'fr-message';
    this.validationMessageTarget.style.display = 'none';
  }
}
