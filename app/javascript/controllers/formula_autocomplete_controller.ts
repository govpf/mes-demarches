import { ApplicationController } from './application_controller';
import tippy, { type Instance as TippyInstance } from 'tippy.js';
import { matchSorter } from 'match-sorter';

/**
 * Interface for column references available in formulas
 */
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

/**
 * FormulaAutocompleteController
 *
 * Provides autocomplete functionality for formula fields.
 * Displays a dropdown with available columns when user types '{'.
 *
 * @example
 * ```haml
 * .cell{ data: {
 *   controller: 'formula-autocomplete',
 *   formula_autocomplete_available_columns_value: columns.to_json
 * }}
 *   = form.text_area :formule_user_expression,
 *     data: {
 *       formula_autocomplete_target: 'textarea',
 *       action: 'input->formula-autocomplete#onInput keydown->formula-autocomplete#onKeyDown'
 *     }
 * ```
 */
export class FormulaAutocompleteController extends ApplicationController {
  static targets = ['textarea'];

  declare readonly textareaTarget: HTMLTextAreaElement;

  static values = {
    availableColumns: Array
  };

  declare readonly availableColumnsValue: ColumnReference[];

  // Tippy.js popup instance
  #popup?: TippyInstance;

  // DOM element for the dropdown menu
  #menuElement?: HTMLElement;

  // Currently filtered columns
  #filteredColumns: ColumnReference[] = [];

  // Selected index in the dropdown
  #selectedIndex = 0;

  // Flag to track if dropdown is visible
  #isDropdownVisible = false;

  /**
   * Initialize controller
   */
  connect() {
    this.createMenuElement();
  }

  /**
   * Cleanup on disconnect
   */
  disconnect() {
    this.destroyPopup();
  }

  /**
   * Handle input events on textarea
   * Detects if user is typing inside {...} and shows/hides dropdown accordingly
   */
  onInput() {
    const textarea = this.textareaTarget;
    const cursorPos = textarea.selectionStart;
    const textBefore = textarea.value.substring(0, cursorPos);

    // Count opening and closing braces to detect if we're inside {...}
    const openBraces = (textBefore.match(/\{/g) || []).length;
    const closeBraces = (textBefore.match(/\}/g) || []).length;

    if (openBraces > closeBraces) {
      // We're inside {...}, extract the query
      const lastOpenBrace = textBefore.lastIndexOf('{');
      const query = textBefore.substring(lastOpenBrace + 1);
      this.showDropdown(query);
    } else {
      this.hideDropdown();
    }
  }

  /**
   * Handle keydown events for keyboard navigation
   */
  onKeyDown(event: KeyboardEvent) {
    if (!this.#isDropdownVisible) return;

    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        this.moveSelection(1);
        break;

      case 'ArrowUp':
        event.preventDefault();
        this.moveSelection(-1);
        break;

      case 'Enter':
        event.preventDefault();
        this.insertSelectedColumn();
        break;

      case 'Escape':
        event.preventDefault();
        this.hideDropdown();
        break;
    }
  }

  /**
   * Show dropdown with filtered columns
   */
  private showDropdown(query: string) {
    this.#filteredColumns = this.filterColumns(query);

    if (this.#filteredColumns.length === 0) {
      this.hideDropdown();
      return;
    }

    this.#selectedIndex = 0;
    this.renderDropdown();

    if (!this.#popup) {
      this.#popup = tippy(this.textareaTarget, {
        getReferenceClientRect: () => this.getCursorRect(),
        content: this.#menuElement!,
        showOnCreate: true,
        interactive: true,
        trigger: 'manual',
        placement: 'bottom-start',
        // pf: on ancre le popup dans le scope du controller (comme
        // shared/tiptap/tags.ts le fait avec editorElement) plutôt que dans
        // document.body. Ça évite que le popup devienne "orphelin" si le
        // composant est re-rendu par turbo.
        appendTo: () => this.element as HTMLElement
      });
    } else {
      this.#popup.setProps({
        getReferenceClientRect: () => this.getCursorRect()
      });
      this.#popup.show();
    }

    // Set ARIA attributes for screen readers
    this.textareaTarget.setAttribute(
      'aria-owns',
      'formula-autocomplete-listbox'
    );
    this.textareaTarget.setAttribute(
      'aria-activedescendant',
      `formula-autocomplete-option-${this.#selectedIndex}`
    );

    this.#isDropdownVisible = true;
  }

  /**
   * Hide dropdown
   */
  private hideDropdown() {
    if (this.#popup) {
      this.#popup.hide();
    }

    // Clear ARIA attributes
    this.textareaTarget.removeAttribute('aria-owns');
    this.textareaTarget.removeAttribute('aria-activedescendant');

    this.#isDropdownVisible = false;
  }

  /**
   * Filter columns based on query using fuzzy matching
   */
  private filterColumns(query: string): ColumnReference[] {
    const columns = this.flattenedColumns();

    if (query === '') {
      // Return all columns if no query
      return columns.slice(0, 10);
    }

    return matchSorter(columns, query, {
      keys: ['label'],
      threshold: matchSorter.rankings.CONTAINS
    }).slice(0, 10);
  }

  /**
   * pf: Aplatit les colonnes et leurs sous-chemins (paths) en une liste plate
   * de suggestions. Chaque colonne contribue elle-même (ex: "Facture" → NB/COUNT,
   * "Numéro DN" → la valeur) PLUS une entrée par sous-chemin avec son label
   * composite (ex: "Facture/Prix HT" → SOMME, "Numéro DN – Date de naissance").
   * L'insertion utilise le label ; formula_editor#convertToColumnIds le remappe
   * ensuite vers l'identifiant interne ({tdc<bloc>/sub_<id>}, {tdc<dn>/date_de_naissance}…).
   */
  private flattenedColumns(): ColumnReference[] {
    const result: ColumnReference[] = [];
    for (const column of this.availableColumnsValue) {
      result.push(column);
      for (const path of column.paths ?? []) {
        result.push({
          id: `${column.id}/${path.path}`,
          label: path.label,
          type: column.type,
          category: column.category
        });
      }
    }
    return result;
  }

  /**
   * Calculate cursor position in textarea for dropdown placement
   * Creates a mirror div to measure text position
   */
  private getCursorRect(): DOMRect {
    const textarea = this.textareaTarget;
    const cursorPos = textarea.selectionStart;
    const textareaRect = textarea.getBoundingClientRect();

    // Create mirror div
    const mirror = document.createElement('div');
    const style = window.getComputedStyle(textarea);

    // Copy styles from textarea to mirror
    const stylesToCopy = [
      'fontFamily',
      'fontSize',
      'fontWeight',
      'lineHeight',
      'letterSpacing',
      'padding',
      'border',
      'width',
      'boxSizing'
    ];

    stylesToCopy.forEach((prop) => {
      const mirrorStyle = mirror.style as unknown as Record<string, string>;
      const computedStyle = style as unknown as Record<string, string>;
      mirrorStyle[prop] = computedStyle[prop];
    });

    mirror.style.position = 'absolute';
    mirror.style.visibility = 'hidden';
    mirror.style.whiteSpace = 'pre-wrap';
    mirror.style.wordWrap = 'break-word';
    mirror.style.overflow = 'hidden';
    mirror.style.top = '0';
    mirror.style.left = '0';

    // Add text up to cursor
    mirror.textContent = textarea.value.substring(0, cursorPos);
    document.body.appendChild(mirror);

    // Add cursor marker
    const span = document.createElement('span');
    span.textContent = '|';
    mirror.appendChild(span);

    // Get span position relative to mirror
    const spanRect = span.getBoundingClientRect();
    const mirrorRect = mirror.getBoundingClientRect();

    document.body.removeChild(mirror);

    // Calculate cursor position relative to textarea, then absolute in viewport
    const relativeX = spanRect.left - mirrorRect.left;
    const relativeY = spanRect.top - mirrorRect.top;

    // Return absolute position in viewport
    return DOMRect.fromRect({
      x: textareaRect.left + relativeX,
      y: textareaRect.top + relativeY - textarea.scrollTop,
      width: 1,
      height: parseInt(style.lineHeight) || 20
    });
  }

  /**
   * Create the dropdown menu element
   */
  private createMenuElement() {
    this.#menuElement = document.createElement('div');
    this.#menuElement.className = 'fr-menu formula-autocomplete-menu';
    this.#menuElement.id = 'formula-autocomplete-listbox';
    this.#menuElement.setAttribute('role', 'listbox');
    this.#menuElement.setAttribute('aria-label', 'Colonnes disponibles');
  }

  /**
   * Render dropdown content with filtered columns
   */
  private renderDropdown() {
    if (!this.#menuElement) return;

    const list = document.createElement('ul');
    list.className = 'fr-menu__list';
    list.setAttribute('role', 'presentation');

    // Add hint
    const hintItem = document.createElement('li');
    hintItem.setAttribute('role', 'presentation');
    hintItem.innerHTML = `
      <span class="fr-hint-text">
        Tapez pour filtrer, ↑/↓ pour naviguer, Entrée pour valider
      </span>
    `;
    list.appendChild(hintItem);

    // Add columns
    this.#filteredColumns.forEach((column, index) => {
      const item = document.createElement('li');
      item.setAttribute('role', 'presentation');

      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'fr-tag fr-tag--sm';
      button.id = `formula-autocomplete-option-${index}`;
      button.setAttribute('role', 'option');
      button.setAttribute(
        'aria-selected',
        index === this.#selectedIndex ? 'true' : 'false'
      );
      button.dataset.columnId = column.id;

      button.innerHTML = `
        <span class="formula-column-label">${this.escapeHtml(column.label)}</span>
        <span class="formula-column-type">${this.getTypeLabel(column.type)}</span>
      `;

      // pf: on attache les listeners programmatiquement plutôt que via
      // data-action Stimulus, car tippy.js déplace le popup dans document.body
      // — hors du scope du controller Stimulus, les data-action ne sont pas
      // enregistrés.
      //
      // `mousedown preventDefault` empêche le textarea de perdre le focus
      // quand l'utilisateur clique sur une suggestion. Sans ça, le blur
      // déclenche l'autosave (data-autosave-on-blur-only) → turbo re-render →
      // le bouton disparaît avant que le click n'aboutisse = flickering et
      // insertion impossible.
      button.addEventListener('mousedown', (event) => event.preventDefault());
      button.addEventListener('click', () => this.insertColumn(column));

      item.appendChild(button);
      list.appendChild(item);
    });

    this.#menuElement.innerHTML = '';
    this.#menuElement.appendChild(list);
  }

  /**
   * Move selection up or down
   */
  private moveSelection(direction: number) {
    const maxIndex = this.#filteredColumns.length - 1;
    this.#selectedIndex = Math.max(
      0,
      Math.min(maxIndex, this.#selectedIndex + direction)
    );
    this.updateSelection();
  }

  /**
   * Update visual selection in dropdown
   */
  private updateSelection() {
    if (!this.#menuElement) return;

    const buttons = this.#menuElement.querySelectorAll('[role="option"]');
    buttons.forEach((button, index) => {
      button.setAttribute(
        'aria-selected',
        index === this.#selectedIndex ? 'true' : 'false'
      );
    });

    // Update aria-activedescendant for screen readers
    this.textareaTarget.setAttribute(
      'aria-activedescendant',
      `formula-autocomplete-option-${this.#selectedIndex}`
    );
  }

  /**
   * Insert the currently selected column
   */
  private insertSelectedColumn() {
    const column = this.#filteredColumns[this.#selectedIndex];
    if (column) {
      this.insertColumn(column);
    }
  }

  /**
   * Insert a column into the textarea at cursor position
   */
  private insertColumn(column: ColumnReference) {
    const textarea = this.textareaTarget;
    const cursorPos = textarea.selectionStart;
    const text = textarea.value;

    // Find the start of the current {...}
    const textBefore = text.substring(0, cursorPos);
    const lastOpenBrace = textBefore.lastIndexOf('{');
    const prefix = text.substring(0, lastOpenBrace);

    // Build new text — skip existing closing brace if present after cursor
    let suffix = text.substring(cursorPos);
    if (suffix.startsWith('}')) {
      suffix = suffix.substring(1);
    }
    const newText = prefix + `{${column.label}}` + suffix;

    textarea.value = newText;

    // Position cursor after }
    const newCursorPos = prefix.length + column.label.length + 2; // +2 for {}
    textarea.setSelectionRange(newCursorPos, newCursorPos);

    // Trigger input event for FormulaEditorController validation
    textarea.dispatchEvent(new Event('input', { bubbles: true }));

    // Dispatch custom event
    this.dispatch('insert');

    this.hideDropdown();

    // Refocus textarea
    textarea.focus();
  }

  /**
   * Get human-readable label for column type
   */
  private getTypeLabel(type: string): string {
    const labels: Record<string, string> = {
      integer: 'nombre entier',
      decimal: 'nombre décimal',
      text: 'texte',
      textarea: 'texte long',
      date: 'date',
      datetime: 'date et heure',
      yes_no: 'oui/non',
      checkbox: 'case à cocher',
      drop_down_list: 'liste déroulante',
      multiple_drop_down_list: 'liste à choix multiples',
      email: 'email',
      phone: 'téléphone',
      address: 'adresse',
      number: 'nombre'
    };

    return labels[type] || this.escapeHtml(type);
  }

  /**
   * Escape HTML to prevent XSS
   */
  private escapeHtml(text: string): string {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  /**
   * Destroy Tippy popup
   */
  private destroyPopup() {
    if (this.#popup) {
      this.#popup.destroy();
      this.#popup = undefined;
    }
  }
}
