# 📋 Spécifications : Migration Attestations v1 → v2

## 🎯 Phase 1 : Migration de base avec coexistence v1/v2

### **Objectifs**
- ✅ Corriger le bug de routage de la PR 168
- ✅ Permettre migration automatique du contenu (texte + formatage simple)
- ✅ Inciter à la migration avec date limite
- ✅ Maintenir possibilité de retour en arrière

### **1. Correction du bug de routage**

**Problème** : `attestation_component.rb` redirige toujours vers v2  
**Solution** : Restaurer la logique conditionnelle

```ruby
# app/components/procedure/card/attestation_component.rb
def edit_attestation_path
  if @procedure.attestation_template&.version == 1
    helpers.edit_admin_procedure_attestation_template_path(@procedure)
  else
    helpers.edit_admin_procedure_attestation_template_v2_path(@procedure)
  end
end
```

### **2. Interface de migration incitative**

**Modification** : `app/views/administrateurs/attestation_templates/edit.html.haml`

```haml
- if @procedure.feature_enabled?(:attestation_v2)
  .fr-mb-6w
    = render Dsfr::AlertComponent.new(state: :warning, title: "⚠️ Attestations v1 supprimées le 1er novembre 2025", heading_level: 'h3') do |c|
      - c.with_body do
        %p L'ancien éditeur d'attestation sera supprimé définitivement le <strong>1er novembre 2025</strong>.
        %p Migrez dès maintenant vers le nouvel éditeur pour préserver votre contenu.
        
        .fr-btns-group.fr-btns-group--inline.fr-mt-3w
          = link_to("🚀 Migrer vers v2 (recommandé)", 
                    migrate_admin_procedure_attestation_template_path(@procedure),
                    class: "fr-btn fr-btn--primary", method: :post,
                    data: { confirm: "Votre contenu sera automatiquement converti. Continuer ?" })
          
          = link_to("📋 Tester v2 (vierge)", 
                    edit_admin_procedure_attestation_template_v2_path(@procedure),
                    class: "fr-btn fr-btn--secondary")
```

### **3. Action de migration automatique**

**Nouvelle route** : `config/routes.rb`
```ruby
resource :attestation_template, only: [:show, :edit, :update, :create] do
  get 'preview', on: :member
  post 'migrate', on: :member  # NOUVELLE
end
```

**Nouveau controller** : `AttestationTemplatesController`
```ruby
def migrate
  v1_template = @procedure.attestation_template_v1
  
  unless v1_template
    redirect_to edit_admin_procedure_attestation_template_path(@procedure), 
                alert: "Aucune attestation v1 trouvée"
    return
  end

  v2_template = build_v2_from_v1(v1_template)
  
  if v2_template.save
    flash.notice = "✅ Attestation migrée vers v2 ! Vous pouvez la modifier ou revenir à v1 si nécessaire."
    redirect_to edit_admin_procedure_attestation_template_v2_path(@procedure)
  else
    flash.alert = "❌ Erreur lors de la migration : #{v2_template.errors.full_messages.join(', ')}"
    redirect_to edit_admin_procedure_attestation_template_path(@procedure)
  end
end

private

def build_v2_from_v1(v1_template)
  # Conversion HTML basique (sans tables)
  tiptap_content = convert_v1_content_to_tiptap(v1_template)
  
  v2_template = @procedure.attestation_templates.build(
    version: 2,
    json_body: tiptap_content,
    activated: v1_template.activated,
    footer: v1_template.footer,
    state: :draft
  )
  
  # Copie des attachments
  v2_template.logo.attach(v1_template.logo.blob) if v1_template.logo.attached?
  v2_template.signature.attach(v1_template.signature.blob) if v1_template.signature.attached?
  
  v2_template
end

def convert_v1_content_to_tiptap(v1_template)
  title_content = html_to_tiptap_basic(v1_template.title || "Titre de l'attestation")
  body_content = html_to_tiptap_basic(v1_template.body || "")
  
  {
    "type" => "doc",
    "content" => [
      {
        "type" => "title",
        "attrs" => { "textAlign" => "center" },
        "content" => title_content
      }
    ] + body_content
  }
end

def html_to_tiptap_basic(html_string)
  return [{ "type" => "text", "text" => html_string }] unless html_string.match?(/<[^>]+>/)
  
  # Conversion basique : <b>, <i>, <u> uniquement
  # Tables et autres balises → texte brut
  doc = Nokogiri::HTML::DocumentFragment.parse(html_string)
  convert_basic_html_nodes(doc.children)
end
```

### **4. Possibilité de retour en arrière**

**Interface v2** : `app/views/administrateurs/attestation_template_v2s/edit.html.haml`
```haml
- if @procedure.attestation_template_v1.present?
  .fr-mb-4w
    = render Dsfr::AlertComponent.new(state: :info, title: "Retour possible", heading_level: 'h4') do |c|
      - c.with_body do
        %p Votre attestation v1 est encore disponible.
        = link_to("← Revenir à l'ancienne version", 
                  edit_admin_procedure_attestation_template_path(@procedure),
                  class: "fr-btn fr-btn--tertiary fr-btn--sm")
```

### **5. Tests et validation**

**Cas de test à couvrir** :
- ✅ Routage conditionnel v1/v2
- ✅ Migration avec formatage simple (`<b>`, `<i>`, `<u>`)
- ✅ Copie des logos et signatures
- ✅ Préservation de l'état d'activation
- ✅ Gestion des erreurs de migration
- ✅ Retour arrière possible

---

## 🚀 Phase 2 : Support complet des tables

### **Objectifs additionnels**
- ✅ Migration intelligente des tables HTML vers Tiptap natif
- ✅ Édition complète des tables en v2
- ✅ Interface améliorée selon complexité du contenu

### **1. Installation TableKit**

**Package.json** : 
```json
{
  "dependencies": {
    "@tiptap/extension-table": "^3.4.1"
  }
}
```

**JavaScript** : `app/javascript/controllers/lazy/tiptap_controller.ts`
```typescript
import { TableKit } from '@tiptap/extension-table'

const editor = new Editor({
  extensions: [
    // Extensions existantes...
    TableKit.configure({
      HTMLAttributes: {
        class: 'table-attestation'
      }
    })
  ]
})
```

### **2. Extension TiptapService pour tables**

```ruby
# app/services/tiptap_service.rb
def node_to_html(node, substitutions, level)
  # ... code existant ...
  
  case node
  # ... autres cas ...
  
  in type: 'table', content:
    "<table class='fr-table'>#{children(content, substitutions, level + 1)}</table>"
  in type: 'tableRow', content:
    "<tr>#{children(content, substitutions, level + 1)}</tr>"
  in type: 'tableCell', content:, **rest
    "<td#{text_align(rest[:attrs])}>#{children(content, substitutions, level + 1)}</td>"
  in type: 'tableHeader', content:, **rest
    "<th#{text_align(rest[:attrs])}>#{children(content, substitutions, level + 1)}</th>"
  end
end
```

### **3. Migration avancée avec tables**

**Controller enrichi** :
```ruby
def convert_v1_content_to_tiptap(v1_template)
  has_tables = v1_template.body&.include?('<table')
  
  if has_tables
    # Migration complète avec tables
    title_content = html_to_tiptap_advanced(v1_template.title || "Titre de l'attestation")
    body_content = html_to_tiptap_advanced(v1_template.body || "")
  else
    # Migration basique
    title_content = html_to_tiptap_basic(v1_template.title || "Titre de l'attestation")
    body_content = html_to_tiptap_basic(v1_template.body || "")
  end
  
  # ... reste identique
end

def html_to_tiptap_advanced(html_string)
  return [{ "type" => "text", "text" => html_string }] unless html_string.match?(/<[^>]+>/)
  
  doc = Nokogiri::HTML::DocumentFragment.parse(html_string)
  convert_advanced_html_nodes(doc.children)
end

def convert_table_to_tiptap(table_node)
  rows = table_node.css('tr').map do |tr|
    cells = tr.css('td, th').map do |cell|
      cell_type = cell.name == 'th' ? 'tableHeader' : 'tableCell'
      {
        "type" => cell_type,
        "content" => convert_cell_content_to_tiptap(cell)
      }
    end
    
    { "type" => "tableRow", "content" => cells }
  end
  
  { "type" => "table", "content" => rows }
end
```

### **4. Interface intelligente selon contenu**

```haml
- content_analysis = analyze_v1_content(@attestation_template)

- if content_analysis[:has_tables]
  .fr-alert.fr-alert--info.fr-mb-4w
    %h4 ✅ Tables détectées (#{content_analysis[:table_count]})
    %p Vos tables seront préservées et éditables dans le nouvel éditeur.

- if content_analysis[:has_unsupported_tags]
  .fr-alert.fr-alert--warning.fr-mb-4w
    %h4 ⚠️ Balises non supportées détectées
    %p Certaines balises (#{content_analysis[:unsupported_tags].join(', ')}) seront converties en texte.

.fr-btns-group.fr-btns-group--inline
  = link_to("🚀 Migrer vers v2 #{content_analysis[:has_tables] ? '(avec tables)' : ''}", 
            migrate_admin_procedure_attestation_template_path(@procedure),
            class: "fr-btn fr-btn--primary", method: :post)
```

### **5. CSS pour tables**

**Styles** : `app/assets/stylesheets/attestation.scss`
```scss
#attestation {
  .table-attestation {
    width: 100%;
    border-collapse: collapse;
    margin: 1rem 0;
    
    th, td {
      border: 1px solid #ddd;
      padding: 8px;
      text-align: left;
    }
    
    th {
      background-color: #f5f5f5;
      font-weight: bold;
    }
  }
}
```

### **6. Tests phase 2**

**Cas de test additionnels** :
- ✅ Migration des tables simples (2x2, 3x3)
- ✅ Migration des tables avec en-têtes
- ✅ Migration des tables avec contenu formaté dans les cellules
- ✅ Édition des tables en v2 (ajout/suppression lignes/colonnes)
- ✅ Rendu PDF avec tables

---

## 📊 Statistiques d'impact (Production PF)

### **Balises HTML trouvées dans les attestations v1** :

| Balise | Démarches impactées | Priorité | Action |
|--------|-------------------|----------|---------|
| `<b>` | **259** | 🔴 CRITIQUE | Migration obligatoire |
| `<u>` | **156** | 🔴 CRITIQUE | Migration obligatoire |
| `<table>` | **89** | 🟠 MAJEUR | Conversion intelligente (Phase 2) |
| `<color>` | **60** | 🟡 MINEUR | Ignorer (couleurs) |
| `<font>` | **53** | 🟡 MINEUR | Ignorer (polices) |
| `<i>` | **39** | 🟠 MOYEN | Migration standard |
| `<strong>` | **2** | ⚪ FAIBLE | Migration standard |
| `<em>` | **2** | ⚪ FAIBLE | Migration standard |

### **Impact total** :
- **415 démarches** avec formatage de base (Phase 1)
- **89 démarches** avec tables (Phase 2)
- **504 démarches** au total nécessitant une migration

---

## 📅 Planning et effort

| Phase | Fonctionnalités | Effort estimé | Impact |
|-------|----------------|---------------|---------|
| **Phase 1** | • Bug routing<br>• Migration basique<br>• UX incitative<br>• Retour arrière | **12-15h** | **415 démarches** sauvées |
| **Phase 2** | • Support tables natif<br>• Migration avancée<br>• Interface intelligente | **8-10h** | **+89 démarches** avec tables |

**Total** : 20-25h pour sauver **504 démarches** avec migration intelligente complète.

### **Livraisons suggérées** :
- **Phase 1** : 2-3 semaines
- **Phase 2** : 1-2 semaines après phase 1

### **ROI de l'investissement** :
- **Coût développement** : ~25h
- **Coût humain re-saisie évité** : ~504h 
- **ROI** : **2000%** (1h dev = 20h économisées)

---

## 🔧 Détails techniques d'implémentation

### **Structure JSON Tiptap pour tables**
```json
{
  "type": "table",
  "content": [
    {
      "type": "tableRow", 
      "content": [
        {
          "type": "tableHeader",
          "content": [{"type": "text", "text": "Nom"}]
        },
        {
          "type": "tableHeader", 
          "content": [{"type": "text", "text": "Prénom"}]
        }
      ]
    },
    {
      "type": "tableRow",
      "content": [
        {
          "type": "tableCell",
          "content": [{"type": "text", "text": "Dupont"}] 
        },
        {
          "type": "tableCell",
          "content": [{"type": "text", "text": "Jean"}]
        }
      ]
    }
  ]
}
```

### **Conversion des marks Tiptap**

| HTML v1 | Tiptap v2 Mark | Action |
|---------|---------------|---------|
| `<b>`, `<strong>` | `{ "type": "bold" }` | ✅ Préservé |
| `<i>`, `<em>` | `{ "type": "italic" }` | ✅ Préservé |
| `<u>` | `{ "type": "underline" }` | ✅ Préservé |
| `<s>`, `<strike>` | `{ "type": "strike" }` | ✅ Préservé |
| `<font>`, `<color>` | - | ❌ Ignoré → texte |

---

## ✅ Critères de succès

### **Phase 1**
- [ ] Correction du bug de routage v1/v2
- [ ] Interface de migration avec date limite
- [ ] Migration automatique du formatage simple
- [ ] Possibilité de retour en arrière
- [ ] Tests passants pour les 415 démarches impactées

### **Phase 2** 
- [ ] Installation et configuration TableKit
- [ ] Extension TiptapService pour les tables
- [ ] Migration des 89 démarches avec tables
- [ ] Interface intelligente selon contenu
- [ ] Tests d'édition des tables en v2

### **Validation globale**
- [ ] 0 régression sur les fonctionnalités existantes
- [ ] 504 démarches migrables sans perte de contenu
- [ ] Interface utilisateur claire et incitative
- [ ] Documentation mise à jour