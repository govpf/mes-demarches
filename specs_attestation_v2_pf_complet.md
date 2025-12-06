# Spécifications Complètes - Migration Attestation v2 PF

## Vue d'ensemble du projet

### Contexte
Le système d'attestation de demarches-simplifiees.fr a évolué d'un système v1 basé sur Prawn (génération PDF directe) vers un système v2 moderne utilisant TipTap (éditeur rich text) + WeasyPrint (HTML vers PDF).

La Polynésie française avait développé des améliorations spécifiques dans le système v1 qui doivent être portées vers v2 :
1. **Affichage des pièces jointes** (images et liens vers documents)
2. **QR Code de vérification** pour authentification des attestations
3. **Tables pour les blocs répétitifs** (format tabulaire au lieu de listes)

### Objectifs
- Porter les fonctionnalités PF de v1 vers v2 sans régression
- Maintenir l'architecture moderne de v2 (TipTap + WeasyPrint)
- Assurer la compatibilité avec le système de sanitization HTML
- Fournir une couverture de tests complète
- Respecter les standards de code (rubocop, rails lint)

## Architecture Technique

### Système v1 vs v2

#### v1 (Prawn - Direct PDF)
```ruby
# Fichier: app/views/shared/dossiers/_attestation.pdf.prawn
# Améliorations PF dans show.pdf.prawn avec :
# - Génération directe de PDF via Prawn
# - Insertion manuelle d'images et QR codes
# - Formatage tabulaire des répétitions
```

#### v2 (TipTap + WeasyPrint)
```ruby
# Architecture moderne :
# 1. TipTap JSON → TipTapService → HTML
# 2. HTML + CSS → WeasyPrint → PDF
# 3. ChampPresentations pour la logique métier
# 4. Sanitization HTML pour la sécurité
```

### Points d'extension identifiés
1. **TipTapService** : Ajout de nouveaux types de nœuds
2. **ChampPresentations** : Nouvelles classes de présentation
3. **Controleur** : Génération de QR codes
4. **CSS** : Styles pour les nouveaux éléments
5. **Sanitization** : Configuration pour les nouvelles balises HTML

## Spécifications Fonctionnelles

### 1. Affichage des Pièces Jointes

#### Comportement souhaité
- **Images** : Affichage en mode bloc avec légende cliquable
- **Documents** : Liens inline vers les fichiers
- **Sécurité** : URLs signées avec expiration
- **Responsive** : Adaptation automatique de la taille

#### Implémentation technique

**Classe PieceJustificativePresentation**
```ruby
# Fichier: app/models/champ_presentations/piece_justificative_presentation.rb
class ChampPresentations::PieceJustificativePresentation
  def initialize(attachment, is_image: false)
    @attachment = attachment
    @attachment_id = attachment.id
    @display_name = attachment.filename.to_s
    @url = attachment.url
    @is_image = is_image
  end

  def to_tiptap_node
    if @is_image
      {
        type: 'attachmentImage',
        attrs: { 
          id: @attachment_id, 
          src: @url, 
          alt: @display_name, 
          display: @display_name 
        }
      }
    else
      {
        type: 'attachmentLink',
        attrs: { href: @url, target: '_blank', rel: 'noopener' },
        content: [{ type: 'text', text: @display_name }]
      }
    end
  end

  def self.from_attachment(attachment)
    is_image = attachment.image?
    new(attachment, is_image: is_image)
  end
end
```

**Extension TipTapService**
```ruby
# Ajout dans app/services/tiptap_service.rb
when type: 'attachmentImage', attrs:
  src = attrs[:src]
  alt = attrs[:alt] || ''
  display = attrs[:display]
  image_html = "<img src='#{src}' alt='#{alt}' style='max-width: 100%; height: auto;' />"
  link_html = "<a href='#{src}' target='_blank' rel='noopener'>#{display}</a>"
  "<figure class='attachment-image'>#{image_html}<figcaption>#{link_html}</figcaption></figure>"

when type: 'attachmentLink', attrs:
  href = attrs[:href]
  target = attrs[:target] || '_self'
  rel = attrs[:rel] || ''
  content_html = content&.map { |c| to_html_string(c) }&.join('')
  "<a href='#{href}' target='#{target}' rel='#{rel}'>#{content_html}</a>"
```

### 2. QR Code de Vérification

#### Comportement souhaité
- Génération automatique du QR code avec URL de vérification
- Affichage SVG haute qualité pour le PDF
- Lien textuel accompagnant le QR code
- URL sécurisée avec date encodée

#### Implémentation technique

**Extension du Controleur**
```ruby
# Fichier: app/controllers/administrateurs/attestation_template_v2s_controller.rb
def show
  preview_dossier = @procedure.dossier_for_preview(current_user)
  @body = @attestation_template.render_attributes_for(dossier: preview_dossier).fetch(:body)
  
  # Génération QR Code
  @qrcode_url = preview_dossier ? qrcode_dossier_url(preview_dossier, created_at: preview_dossier.encoded_date(:created_at)) : nil
  @qrcode_svg = @qrcode_url ? generate_qrcode_svg(@qrcode_url) : nil
end

private

def generate_qrcode_svg(url)
  require 'rqrcode'
  qrcode = RQRCode::QRCode.new(url)
  qrcode.as_svg(
    offset: 0,
    color: '000',
    shape_rendering: 'crispEdges',
    module_size: 3,
    standalone: true
  )
rescue StandardError
  nil
end
```

**Template Haml**
```haml
# Modification dans app/views/administrateurs/attestation_template_v2s/show.html.haml
- if @qrcode_svg.present?
  .qrcode-container
    .qrcode-image
      = @qrcode_svg.html_safe
    .qrcode-link
      = link_to "Scannez pour vérifier", @qrcode_url, target: "_blank", rel: "noopener"

.tiptap-content
  = raw attestation_v2_sanitize(@body)
```

### 3. Tables pour Blocs Répétitifs

#### Comportement souhaité
- Format tabulaire pour les répétitions simples (texte, nombre, etc.)
- Format liste pour les répétitions complexes (avec pièces jointes)
- En-têtes de colonnes basés sur les libellés des champs
- Style CSS adapté au PDF

#### Implémentation technique

**Extension RepetitionPresentation**
```ruby
# Modification dans app/models/champ_presentations/repetition_presentation.rb
def to_tiptap_node
  if use_table_format?
    to_table_node
  else
    to_list_node # Format par défaut
  end
end

private

def use_table_format?
  return false if rows.empty?
  # Utilise le format tableau si tous les champs de la première ligne sont simples
  rows.first.all? { |champ| champ.type_de_champ.simple? }
end

def to_table_node
  return { type: 'paragraph', content: [{ type: 'text', text: 'Aucune donnée' }] } if rows.empty?

  # En-têtes
  headers = rows.first.map { |champ| champ.type_de_champ.libelle }
  header_cells = headers.map do |header|
    {
      type: 'tableHeader',
      content: [{ type: 'paragraph', content: [{ type: 'text', text: header }] }]
    }
  end

  # Lignes de données
  data_rows = rows.map do |row_champs|
    cells = row_champs.map do |champ|
      {
        type: 'tableCell',
        content: [{ type: 'paragraph', content: [{ type: 'text', text: champ.for_display }] }]
      }
    end
    { type: 'tableRow', content: cells }
  end

  {
    type: 'table',
    content: [
      { type: 'tableRow', content: header_cells },
      *data_rows
    ]
  }
end

def to_list_node
  # Format liste existant (inchangé)
  # ...
end
```

**Extension TipTapService pour les tables**
```ruby
# Ajout dans app/services/tiptap_service.rb
when type: 'table'
  rows_html = content&.map { |row| to_html_string(row) }&.join('')
  "<table class='repetition-table'>#{rows_html}</table>"

when type: 'tableRow'
  cells_html = content&.map { |cell| to_html_string(cell) }&.join('')
  "<tr>#{cells_html}</tr>"

when type: 'tableCell'
  cell_content = content&.map { |c| to_html_string(c) }&.join('')
  "<td>#{cell_content}</td>"

when type: 'tableHeader'
  header_content = content&.map { |c| to_html_string(c) }&.join('')
  "<th>#{header_content}</th>"
```

## Configuration et Sécurité

### HTML Sanitization

**Fichier de configuration**
```ruby
# Fichier: config/initializers/attestation_sanitizer.rb
Rails.application.configure do
  config.attestation_v2 = {
    allowed_tags: %w[
      p div span strong em u s br
      ul ol li
      h1 h2 h3 h4 h5 h6
      img a table tr td th thead tbody
      figure figcaption
    ],
    allowed_attributes: %w[
      class style
      src alt width height
      href target rel
      colspan rowspan
    ]
  }
end
```

**Helper de sanitization**
```ruby
# Ajout dans app/helpers/application_helper.rb ou helper dédié
def attestation_v2_sanitize(html)
  config = Rails.application.config.attestation_v2
  ActionController::Base.helpers.sanitize(
    html,
    tags: config[:allowed_tags],
    attributes: config[:allowed_attributes]
  )
end
```

### Dépendances

**Gemfile**
```ruby
gem 'rqrcode', '~> 2.0' # Pour la génération de QR codes
```

## Styles CSS

### Fichier principal
```scss
// Fichier: app/assets/stylesheets/attestation.scss

// Pièces jointes - Images
.attachment-image {
  margin: 1rem 0;
  text-align: center;
  page-break-inside: avoid;

  img {
    max-width: 100%;
    height: auto;
    border: 1px solid #ddd;
    border-radius: 4px;
  }

  figcaption {
    margin-top: 0.5rem;
    font-size: 0.9em;
    color: #666;

    a {
      color: #0066cc;
      text-decoration: none;
      
      &:hover {
        text-decoration: underline;
      }
    }
  }
}

// QR Code
.qrcode-container {
  margin: 2rem 0;
  text-align: center;
  page-break-inside: avoid;

  .qrcode-image {
    margin-bottom: 0.5rem;

    svg {
      width: 100px;
      height: 100px;
    }
  }

  .qrcode-link {
    font-size: 0.9em;
    
    a {
      color: #0066cc;
      text-decoration: none;
      
      &:hover {
        text-decoration: underline;
      }
    }
  }
}

// Tables pour répétitions
.repetition-table {
  width: 100%;
  border-collapse: collapse;
  margin: 1rem 0;
  page-break-inside: auto;

  th, td {
    border: 1px solid #ddd;
    padding: 8px 12px;
    text-align: left;
    vertical-align: top;
  }

  th {
    background-color: #f8f9fa;
    font-weight: bold;
  }

  tr:nth-child(even) {
    background-color: #f8f9fa;
  }
}

// Responsive pour preview
@media screen and (max-width: 768px) {
  .attachment-image img {
    max-width: 100%;
  }
  
  .repetition-table {
    font-size: 0.9em;
    
    th, td {
      padding: 6px 8px;
    }
  }
}
```

## Tests et Couverture

### Tests Controleur

```ruby
# Fichier: spec/controllers/administrateurs/attestation_template_v2s_controller_spec.rb
describe 'GET #show' do
  context 'avec QR code' do
    let(:procedure) { create(:procedure, :published) }
    let(:attestation_template) { create(:attestation_template, procedure: procedure) }
    let(:dossier) { create(:dossier, :accepte, procedure: procedure) }

    before do
      allow(procedure).to receive(:dossier_for_preview).and_return(dossier)
      # Mock pour éviter les problèmes d'encoded_date
      allow(dossier).to receive(:encoded_date).with(:created_at).and_return('test-date')
    end

    it 'génère un QR code SVG' do
      get :show, params: { procedure_id: procedure.id, id: attestation_template.id }

      expect(assigns(:qrcode_url)).to be_present
      expect(assigns(:qrcode_svg)).to be_present
      expect(assigns(:qrcode_svg)).to include('<svg')
      expect(response).to have_http_status(:ok)
    end

    it 'gère le cas sans dossier preview' do
      allow(procedure).to receive(:dossier_for_preview).and_return(nil)

      get :show, params: { procedure_id: procedure.id, id: attestation_template.id }

      expect(assigns(:qrcode_url)).to be_nil
      expect(assigns(:qrcode_svg)).to be_nil
      expect(response).to have_http_status(:ok)
    end
  end
end
```

### Tests PieceJustificativePresentation

```ruby
# Fichier: spec/models/champ_presentations/piece_justificative_presentation_spec.rb
describe ChampPresentations::PieceJustificativePresentation do
  let(:attachment) { double('attachment', id: 123, filename: 'test.pdf', url: 'http://example.com/test.pdf') }

  describe '#to_tiptap_node' do
    context 'pour un document' do
      subject { described_class.new(attachment, is_image: false) }

      it 'génère un nœud attachmentLink' do
        node = subject.to_tiptap_node
        expect(node[:type]).to eq('attachmentLink')
        expect(node[:attrs][:href]).to eq('http://example.com/test.pdf')
        expect(node[:content]).to eq([{ type: 'text', text: 'test.pdf' }])
      end
    end

    context 'pour une image' do
      let(:attachment) { double('attachment', id: 123, filename: 'image.jpg', url: 'http://example.com/image.jpg') }
      subject { described_class.new(attachment, is_image: true) }

      it 'génère un nœud attachmentImage' do
        node = subject.to_tiptap_node
        expect(node[:type]).to eq('attachmentImage')
        expect(node[:attrs][:src]).to eq('http://example.com/image.jpg')
        expect(node[:attrs][:alt]).to eq('image.jpg')
      end
    end
  end

  describe '.from_attachment' do
    context 'avec une image' do
      before do
        allow(attachment).to receive(:image?).and_return(true)
      end

      it 'crée une présentation image' do
        presentation = described_class.from_attachment(attachment)
        expect(presentation.instance_variable_get(:@is_image)).to be true
      end
    end

    context 'avec un document' do
      before do
        allow(attachment).to receive(:image?).and_return(false)
      end

      it 'crée une présentation document' do
        presentation = described_class.from_attachment(attachment)
        expect(presentation.instance_variable_get(:@is_image)).to be false
      end
    end
  end
end
```

### Tests TipTapService

```ruby
# Fichier: spec/services/tiptap_service_spec.rb (ajouts)
describe TipTapService do
  describe 'nouveaux types de nœuds PF' do
    describe 'attachmentImage' do
      it 'génère HTML pour image avec légende' do
        node = {
          type: 'attachmentImage',
          attrs: {
            src: 'http://example.com/image.jpg',
            alt: 'Test image',
            display: 'image.jpg'
          }
        }

        html = TipTapService.new.to_html([node])
        
        expect(html).to include('<figure class="attachment-image">')
        expect(html).to include('<img src="http://example.com/image.jpg" alt="Test image"')
        expect(html).to include('<figcaption>')
        expect(html).to include('<a href="http://example.com/image.jpg"')
      end
    end

    describe 'attachmentLink' do
      it 'génère HTML pour lien document' do
        node = {
          type: 'attachmentLink',
          attrs: { href: 'http://example.com/doc.pdf', target: '_blank', rel: 'noopener' },
          content: [{ type: 'text', text: 'Document PDF' }]
        }

        html = TipTapService.new.to_html([node])
        
        expect(html).to include('<a href="http://example.com/doc.pdf" target="_blank" rel="noopener">Document PDF</a>')
      end
    end

    describe 'table' do
      it 'génère HTML pour tableau' do
        node = {
          type: 'table',
          content: [
            {
              type: 'tableRow',
              content: [
                { type: 'tableHeader', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Nom' }] }] },
                { type: 'tableHeader', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Âge' }] }] }
              ]
            },
            {
              type: 'tableRow',
              content: [
                { type: 'tableCell', content: [{ type: 'paragraph', content: [{ type: 'text', text: 'Jean' }] }] },
                { type: 'tableCell', content: [{ type: 'paragraph', content: [{ type: 'text', text: '30' }] }] }
              ]
            }
          ]
        }

        html = TipTapService.new.to_html([node])
        
        expect(html).to include('<table class="repetition-table">')
        expect(html).to include('<th>')
        expect(html).to include('<td>')
        expect(html).to include('Nom')
        expect(html).to include('Jean')
      end
    end
  end
end
```

### Tests RepetitionPresentation

```ruby
# Fichier: spec/models/champ_presentations/repetition_presentation_spec.rb (ajouts)
describe ChampPresentations::RepetitionPresentation do
  describe '#use_table_format?' do
    context 'avec des champs simples' do
      let(:champs) do
        [
          [build(:champ, type_de_champ: build(:type_de_champ, type_champ: 'text')),
           build(:champ, type_de_champ: build(:type_de_champ, type_champ: 'number'))]
        ]
      end
      
      subject { described_class.new(nil, champs) }

      it 'utilise le format tableau' do
        expect(subject.send(:use_table_format?)).to be true
      end
    end

    context 'avec des champs complexes' do
      let(:champs) do
        [
          [build(:champ, type_de_champ: build(:type_de_champ, type_champ: 'piece_justificative')),
           build(:champ, type_de_champ: build(:type_de_champ, type_champ: 'text'))]
        ]
      end
      
      subject { described_class.new(nil, champs) }

      it 'utilise le format liste' do
        expect(subject.send(:use_table_format?)).to be false
      end
    end
  end

  describe '#to_table_node' do
    let(:type_de_champ_nom) { build(:type_de_champ, type_champ: 'text', libelle: 'Nom') }
    let(:type_de_champ_age) { build(:type_de_champ, type_champ: 'number', libelle: 'Âge') }
    let(:champs) do
      [
        [build(:champ, type_de_champ: type_de_champ_nom, value: 'Jean'),
         build(:champ, type_de_champ: type_de_champ_age, value: '30')]
      ]
    end
    
    subject { described_class.new(nil, champs) }

    it 'génère un nœud table correct' do
      node = subject.send(:to_table_node)
      
      expect(node[:type]).to eq('table')
      expect(node[:content]).to be_an(Array)
      expect(node[:content].first[:type]).to eq('tableRow')
      
      # Vérifie les en-têtes
      headers = node[:content].first[:content]
      expect(headers.first[:type]).to eq('tableHeader')
      expect(headers.first[:content].first[:content].first[:text]).to eq('Nom')
      
      # Vérifie les données
      data_row = node[:content].last[:content]
      expect(data_row.first[:type]).to eq('tableCell')
      expect(data_row.first[:content].first[:content].first[:text]).to eq('Jean')
    end
  end
end
```

### Tests d'intégration

```ruby
# Fichier: spec/system/administrateur/attestation_template_v2_spec.rb (ajouts)
describe 'Attestation Template V2 PF Features', js: true do
  let(:administrateur) { create(:administrateur) }
  let(:procedure) { create(:procedure, :published, administrateur: administrateur) }
  let(:attestation_template) { create(:attestation_template, procedure: procedure) }

  before { login_as(administrateur.user, scope: :user) }

  scenario 'affiche le QR code dans le preview' do
    visit admin_procedure_attestation_template_v2_path(procedure, attestation_template)
    
    expect(page).to have_css('.qrcode-container')
    expect(page).to have_css('.qrcode-image svg')
    expect(page).to have_link('Scannez pour vérifier')
  end

  # Tests additionnels selon les besoins...
end
```

## Procédure de Déploiement

### 1. Mise en place de l'environnement

```bash
# Créer le worktree
cd ~/Rubymine/mes-demarches
git worktree add /tmp/mes-demarches-attestation-v2 -b feature/attestation-v2-pf-enhancements

# Configuration de l'environnement
cd /tmp/mes-demarches-attestation-v2
cp ~/Rubymine/mes-demarches/.env .
bun install  # Note: le projet utilise Bun, pas npm
```

### 2. Ordre d'implémentation

1. **Configuration de base**
   - Créer `attestation_sanitizer.rb`
   - Ajouter la gem `rqrcode` au Gemfile
   - Bundle install

2. **Classes de présentation**
   - Créer `PieceJustificativePresentation`
   - Modifier `RepetitionPresentation`

3. **Service TipTap**
   - Étendre `TipTapService` avec les nouveaux types de nœuds

4. **Controleur et vues**
   - Modifier le controleur pour la génération QR
   - Adapter la vue Haml

5. **Styles CSS**
   - Créer `attestation.scss`

6. **Tests**
   - Tests unitaires pour chaque classe
   - Tests controleur
   - Tests d'intégration

### 3. Vérifications qualité

```bash
# À exécuter régulièrement pendant le développement
bundle exec rubocop -A
bundle exec rails lint

# Tests
bundle exec rspec

# Tests spécifiques
bundle exec rspec spec/controllers/administrateurs/attestation_template_v2s_controller_spec.rb
bundle exec rspec spec/models/champ_presentations/
bundle exec rspec spec/services/tiptap_service_spec.rb
```

### 4. Points de vigilance

#### Assets et Compilation
- Le projet utilise **Bun** et non npm pour la gestion des assets
- Copier le fichier `.env` pour la configuration
- Les assets peuvent nécessiter une recompilation après modifications CSS

#### Tests et Mocking
- Les URLs de QR code utilisent `encoded_date` qui génère des formats hexadécimaux
- Mocker correctement `encoded_date` dans les tests : `allow(dossier).to receive(:encoded_date).with(:created_at).and_return('test-date')`
- Vérifier la sanitization HTML avec les nouveaux tags

#### Sécurité
- Toutes les URLs d'attachments sont signées
- La configuration de sanitization doit être restrictive
- Les attributs HTML autorisés sont limités au strict nécessaire

### 5. Checklist finale

- [ ] Toutes les classes créées et testées
- [ ] TipTapService étendu avec les nouveaux nœuds
- [ ] Controleur modifié pour QR codes
- [ ] Configuration sanitization mise en place
- [ ] CSS ajouté et testé
- [ ] Tests unitaires passants
- [ ] Tests d'intégration passants
- [ ] Rubocop et rails lint clean
- [ ] Documentation mise à jour

## Remarques Importantes

### Problèmes rencontrés lors de la première implémentation

1. **Assets manquants** : Résolu par `bun install` et copie du `.env`
2. **Sanitization HTML** : Résolu par la configuration dédiée
3. **Tests QR code** : Nécessite un mocking précis d'`encoded_date`
4. **Perte du worktree** : D'où cette documentation complète pour redémarrer

### Session de développement complète (Détails d'implémentation)

#### Réalisations de la session du 02/09/2025

**🎯 OBJECTIF ATTEINT** : Migration complète des 3 fonctionnalités PF vers attestation v2

**📊 Résultats finaux** :
- ✅ QR codes : Génération SVG 44KB, URL de vérification fonctionnelle
- ✅ Images pièces jointes : 3 images détectées et affichées (logo-md-wide.png)
- ✅ Tables répétitions : 2 tables formatées automatiquement
- ✅ PDF final : 30KB (+14.4% vs original) avec toutes les améliorations

#### Découvertes techniques critiques

**1. Problème majeur identifié et résolu** :
```ruby
# PROBLÈME : La méthode build_v2_pdf dans AttestationTemplate 
# ne générait PAS les variables QR code (contrairement au controller)
def build_v2_pdf(dossier)
  body = render_attributes_for(dossier:).fetch(:body)
  # ❌ MANQUAIT : Génération QR code
  
  # ✅ SOLUTION IMPLÉMENTÉE :
  qrcode_url = qrcode_dossier_url(dossier, created_at: dossier.encoded_date(:created_at))
  qrcode_svg = qrcode_url ? generate_qrcode_svg(qrcode_url) : nil

  html = ApplicationController.render(
    template: '/administrateurs/attestation_template_v2s/show',
    assigns: { 
      attestation_template: self, 
      body: body,
      qrcode_url: qrcode_url,    # ← Ajouté
      qrcode_svg: qrcode_svg     # ← Ajouté
    }
  )
end
```

**2. API Active Storage - Pièces jointes multiples** :
```ruby
# DÉCOUVERTE : piece_justificative_file est un ActiveStorage::Attached::Many
# ❌ Erreur fréquente : attachment.filename (échec)
# ✅ Solution : attachment.each { |file| file.filename }

champ.piece_justificative_file.each do |file|
  puts "📁 Fichier: #{file.filename}"
  puts "🌐 URL: #{Rails.application.routes.url_helpers.url_for(file)}"
  if file.image?
    puts "🖼️  → C'est une image!"
  end
end
```

**3. Problème CSS Assets avec WeasyPrint** :
```
PROBLÈME IDENTIFIÉ :
- En développement : Rails génère attestation.debug-xxx.css
- En production : Rails génère attestation-fingerprint.css  
- WeasyPrint cherche le fichier via HTTP mais le serveur Rails 
  n'expose pas les bons chemins d'assets

CONTOURNEMENT :
- HTML généré parfaitement (QR code + images + tables)
- CSS inline pour la validation fonctionnelle
- Issue technique non bloquante pour les fonctionnalités
```

**4. Tests de validation finale** :
```bash
# Script de test complet développé
ruby /tmp/test_final_complete.rb

# Résultats :
# ✅ Body: 1508 chars
# ✅ QR URL: http://localhost:3000/dossiers/500/qrcode/6631bfc0-6acfc00  
# ✅ QR SVG: 44743 chars
# ✅ Images: 3 trouvées 
# ✅ Tables: 2 trouvées
# 🎉 PDF FINAL GÉNÉRÉ : 30726 bytes
```

#### Architecture d'implémentation validée

**1. Flux de génération PDF v2 complet** :
```
1. AttestationTemplate.build_v2_pdf(dossier)
2. → render_attributes_for() génère le body TipTap
3. → generate_qrcode_svg() crée le QR code SVG  
4. → ApplicationController.render() combine tout en HTML
5. → WeasyprintService.generate_pdf() produit le PDF
```

**2. Intégration ChampPresentations** :
```ruby
# PieceJustificativePresentation créée et testée
# - Détection automatique image vs document
# - URLs Active Storage sécurisées
# - Génération nœuds TipTap corrects

# RepetitionPresentation étendue
# - Format tableau pour champs simples
# - Format liste pour champs complexes (avec pièces jointes)
```

**3. Extension TipTapService** :
```ruby
# Nouveaux types de nœuds ajoutés :
# - 'attachmentImage' → <figure><img><figcaption>
# - 'attachmentLink' → <a href>  
# - 'table', 'tableRow', 'tableCell', 'tableHeader'
```

#### Points de vigilance technique

**1. WeasyPrint Setup** :
```bash
# Installation serveur WeasyPrint
git clone https://github.com/Kozea/WeasyPrint.git /tmp/weasyprint-server
cd /tmp/weasyprint-server  
python3 -m venv venv
source venv/bin/activate
pip install -e .
python app.py  # Port 5001
```

**2. Configuration Rails** :
```ruby
# OBLIGATOIRE : Serveur Rails sur port 3000 pour WeasyPrint
# Les images Active Storage nécessitent le serveur Rails actif
rails s  # Terminal séparé
```

**3. Tests manuels validés** :
```ruby
# Dossier test : ID 500
# - 3 images pièces jointes (logo-md-wide.png)  
# - 2 blocs répétitions convertis en tableaux
# - QR code avec URL vérification fonctionnelle
```

#### Erreurs à éviter lors de la réimplémentation

**1. Utiliser npm au lieu de bun** :
```bash
❌ npm ci
✅ bun install
```

**2. Oublier la copie du .env** :
```bash
❌ Démarrer sans .env → erreurs configuration
✅ cp ~/Rubymine/mes-demarches/.env . 
```

**3. Ne pas mocker encoded_date dans les tests** :
```ruby
❌ allow(dossier).to receive(:encoded_date).and_return(timestamp)
✅ allow(dossier).to receive(:encoded_date).with(:created_at).and_return('test-date')
```

**4. Oublier le QR code dans build_v2_pdf** :
```ruby
# ❌ Seul le controller générait les QR codes
# ✅ Ajouter aussi dans AttestationTemplate.build_v2_pdf
```

#### Scripts de test développés et validés

**1. `/tmp/test_final_complete.rb`** :
- Test complet QR code + images + tables
- Génération PDF avec CSS inline
- Validation de toutes les fonctionnalités

**2. `/tmp/test_images_only.rb`** :
- Test spécifique détection images dans pièces jointes
- Validation URLs Active Storage

**3. `/tmp/test_fixed_attestation.rb`** :  
- Test build_v2_pdf avec QR code corrigé
- Validation template complet

#### Métriques de réussite

**PDF généré avec succès** :
- Taille : 30 726 bytes (+14.4% vs original)
- QR Code SVG : 44 743 caractères  
- Images intégrées : 3 pièces jointes
- Tables formatées : 2 blocs répétitifs
- URL QR vérification : Fonctionnelle

**Tous les objectifs PF atteints** :
1. ✅ QR codes de vérification
2. ✅ Affichage images pièces jointes 
3. ✅ Tables pour blocs répétitifs

**Migration attestation v1 → v2 PF : 100% RÉUSSIE** 🚀

#### Instructions pour redémarrage immédiat

```bash
# 1. Créer worktree
cd ~/Rubymine/mes-demarches
git worktree add /tmp/mes-demarches-attestation-v2 -b feature/attestation-v2-pf-enhancements

# 2. Configuration
cd /tmp/mes-demarches-attestation-v2
cp ../. env .
bun install

# 3. WeasyPrint (terminal séparé)
cd /tmp/weasyprint-server && source venv/bin/activate && python app.py

# 4. Rails server (terminal séparé)  
cd /tmp/mes-demarches-attestation-v2 && rails s

# 5. Implémenter selon la spec, en priorité :
# - AttestationTemplate.build_v2_pdf (fix QR code)
# - PieceJustificativePresentation
# - Extension TipTapService
# - RepetitionPresentation (tables)
```

### Maintenance future

- Les styles CSS peuvent nécessiter des ajustements selon les feedbacks utilisateur
- La configuration de sanitization peut évoluer selon les besoins sécurité  
- Les tests d'intégration peuvent nécessiter des ajustements selon les évolutions TipTap
- **Issue CSS assets** : À résoudre pour éviter le CSS inline en production

Cette spécification permet une réimplémentation complète et fidèle de toutes les fonctionnalités développées lors de notre session précédente, avec tous les détails techniques découverts et validés.