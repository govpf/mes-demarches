# Développement : Navigation contextuelle entre personas

## Vue d'ensemble
Amélioration de la navigation entre personas (usager/instructeur/administrateur) pour permettre des transitions contextuelles intelligentes plutôt que de toujours revenir aux listes par défaut.

## Objectif principal
Quand un utilisateur change de persona, le système doit essayer de le maintenir dans son contexte actuel (même dossier/démarche) si les permissions le permettent.

## Contraintes critiques du fork

### 1. Feature flag par utilisateur
- La fonctionnalité doit être activable **par utilisateur** et non globalement
- Permet de tester avec des utilisateurs spécifiques avant généralisation
- Utiliser le système Flipper existant dans l'application

### 2. Minimiser les modifications pour faciliter les merges upstream
- **ÉVITER** de modifier les fichiers existants autant que possible
- **PRIVILÉGIER** l'ajout de nouvelles méthodes plutôt que la modification
- **UTILISER** l'héritage, les concerns et les decorators
- **DOCUMENTER** clairement toute modification inévitable

### 3. Documentation des modifications
- **OBLIGATOIRE** : Chaque modification doit être commentée avec `# pf: description`
- **MISE À JOUR** : Le fichier `french_polynesia.md` doit être mis à jour avec la nouvelle fonctionnalité

## Cas d'usage à implémenter

### 1. Usager → Instructeur
- **Contexte** : Usager sur un dossier
- **Condition** : L'usager est instructeur de la procédure du dossier
- **Redirection** : Page d'instruction du même dossier
- **Fallback** : Liste des procédures de l'instructeur

### 2. Instructeur → Usager
- **Contexte** : Instructeur sur un dossier
- **Condition** : Le dossier appartient à l'instructeur
- **Redirection** : Page usager du même dossier
- **Fallback** : Liste des dossiers de l'usager

### 3. Administrateur → Instructeur
- **Contexte** : Administrateur sur une démarche
- **Condition** : L'administrateur est aussi instructeur de cette démarche
- **Redirection** : Page d'instruction de la démarche
- **Fallback** : Liste des procédures de l'instructeur

### 4. Instructeur → Administrateur
- **Contexte** : Instructeur sur une démarche ou un dossier
- **Condition** : L'instructeur est administrateur de la procédure
- **Redirection** : Page d'administration de la démarche
- **Fallback** : Liste des procédures de l'administrateur

## Architecture technique (optimisée pour le fork)

### Stratégie d'implémentation minimale

#### 1. Créer un nouveau concern (NOUVEAU FICHIER)
```ruby
# app/controllers/concerns/contextual_navigation_concern.rb
# pf: navigation contextuelle entre personas pour améliorer l'UX des créateurs de formulaires
module ContextualNavigationConcern
  extend ActiveSupport::Concern

  included do
    helper_method :contextual_persona_enabled?
    helper_method :contextual_redirect_path_for_profile
  end

  private

  def contextual_persona_enabled?
    return false unless current_user
    Flipper.enabled?(:contextual_persona_navigation, current_user)
  end

  def contextual_redirect_path_for_profile(target_profile)
    return nil unless contextual_persona_enabled?
    
    # Logique de redirection contextuelle
    # Retourne nil pour utiliser le comportement par défaut
  end
end
```

#### 2. Créer un helper decorator (NOUVEAU FICHIER)
```ruby
# app/helpers/contextual_navigation_helper.rb
# pf: helper pour la navigation contextuelle entre personas
module ContextualNavigationHelper
  def contextual_or_default_path_for_profile(target_profile)
    if contextual_persona_enabled?
      contextual_path = build_contextual_path(target_profile)
      return contextual_path if contextual_path
    end
    
    # Fallback vers le comportement existant
    root_path_info_for_profile(target_profile).first
  end

  private

  def build_contextual_path(target_profile)
    # Implémentation de la logique contextuelle
  end
end
```

#### 3. Modification MINIMALE du dropdown (SEULE modification d'un fichier existant)
```haml
# app/views/layouts/_account_dropdown.haml
# Changement minimal : remplacer uniquement les paths

- if user_signed_in? && nav_bar_profile != :user
  %li
    -# pf: redirection contextuelle lors du changement de persona (feature flag)
    - path = defined?(contextual_or_default_path_for_profile) ? contextual_or_default_path_for_profile(:user) : dossiers_path
    = link_to path, class: "fr-nav__link" do
      %span.fr-icon-refresh-line.fr-icon--sm
      = t('go_user', scope: [:layouts])

- if instructeur_signed_in? && nav_bar_profile != :instructeur
  %li
    -# pf: redirection contextuelle lors du changement de persona (feature flag)
    - path = defined?(contextual_or_default_path_for_profile) ? contextual_or_default_path_for_profile(:instructeur) : instructeur_procedures_path
    = link_to path, class: "fr-nav__link" do
      %span.fr-icon-refresh-line.fr-icon--sm
      = t('go_instructor', scope: [:layouts])

- if administrateur_signed_in? && nav_bar_profile != :administrateur
  %li
    -# pf: redirection contextuelle lors du changement de persona (feature flag)
    - path = defined?(contextual_or_default_path_for_profile) ? contextual_or_default_path_for_profile(:administrateur) : admin_procedures_path
    = link_to path, class: "fr-nav__link" do
      %span.fr-icon-refresh-line.fr-icon--sm
      = t('go_admin', scope: [:layouts])
```

### Configuration Flipper

```ruby
# config/initializers/flipper.rb (ou ajouter à l'existant)
# pf: feature flag pour la navigation contextuelle entre personas
Flipper.register(:contextual_persona_navigation) do |actor|
  actor.respond_to?(:user?) && actor.user?
end

# Dans la console ou via l'interface Flipper
# Activer pour des users spécifiques
Flipper.enable(:contextual_persona_navigation, User.find_by(email: 'test@example.com'))
```

### Implémentation détaillée du concern

```ruby
# app/controllers/concerns/contextual_navigation_concern.rb
# pf: navigation contextuelle entre personas pour améliorer l'UX des créateurs de formulaires
module ContextualNavigationConcern
  extend ActiveSupport::Concern

  included do
    # pf: inclusion dans ApplicationController requise
    helper_method :contextual_persona_enabled?
    helper_method :contextual_redirect_path_for_profile
  end

  private

  def contextual_persona_enabled?
    return false unless current_user
    Flipper.enabled?(:contextual_persona_navigation, current_user)
  end

  def contextual_redirect_path_for_profile(target_profile)
    return nil unless contextual_persona_enabled?
    
    context = current_context_info
    return nil if context.empty?

    case target_profile
    when :instructeur
      build_instructeur_contextual_path(context)
    when :user  
      build_user_contextual_path(context)
    when :administrateur
      build_administrateur_contextual_path(context)
    else
      nil
    end
  rescue StandardError => e
    Rails.logger.error "[ContextualNav] Error: #{e.message}"
    nil
  end

  def current_context_info
    @current_context_info ||= begin
      case controller_path
      when /^users\/dossiers/
        { type: :dossier, id: params[:id] }
      when /^instructeurs\/dossiers/
        { type: :dossier, id: params[:dossier_id] }
      when /^instructeurs\/procedures/
        if params[:dossier_id].present?
          { type: :dossier, id: params[:dossier_id] }
        else
          { type: :procedure, id: params[:procedure_id] }
        end
      when /^administrateurs\/procedures/
        { type: :procedure, id: params[:id] || params[:procedure_id] }
      else
        {}
      end
    end
  end

  def build_instructeur_contextual_path(context)
    case context[:type]
    when :dossier
      if can_access_dossier_as_instructeur?(context[:id])
        dossier = Dossier.find(context[:id])
        instructeur_dossier_path(procedure_id: dossier.procedure_id, dossier_id: context[:id])
      end
    when :procedure
      if can_access_procedure_as_instructeur?(context[:id])
        instructeur_procedure_path(procedure_id: context[:id])
      end
    end
  end

  def build_user_contextual_path(context)
    if context[:type] == :dossier && can_access_dossier_as_user?(context[:id])
      dossier_path(context[:id])
    end
  end

  def build_administrateur_contextual_path(context)
    procedure_id = case context[:type]
    when :procedure
      context[:id]
    when :dossier
      Dossier.find_by(id: context[:id])&.procedure_id
    end

    if procedure_id && can_access_procedure_as_administrateur?(procedure_id)
      admin_procedure_path(procedure_id)
    end
  end

  def can_access_dossier_as_instructeur?(dossier_id)
    return false unless instructeur_signed_in?
    dossier = Dossier.find_by(id: dossier_id)
    return false unless dossier
    
    current_instructeur.procedures.exists?(id: dossier.procedure_id)
  end

  def can_access_dossier_as_user?(dossier_id)
    return false unless user_signed_in?
    current_user.dossiers.exists?(id: dossier_id)
  end

  def can_access_procedure_as_administrateur?(procedure_id)
    return false unless administrateur_signed_in?
    current_administrateur.procedures.exists?(id: procedure_id)
  end

  def can_access_procedure_as_instructeur?(procedure_id)
    return false unless instructeur_signed_in?
    current_instructeur.procedures.exists?(id: procedure_id)
  end
end
```

### Modification d'ApplicationController

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  # ... code existant ...
  
  # pf: ajout du concern pour la navigation contextuelle entre personas
  include ContextualNavigationConcern
  
  # ... reste du code ...
end
```

## Mise à jour de french_polynesia.md

Ajouter dans la section appropriée :

```markdown
## Navigation contextuelle entre personas

### Description
Les utilisateurs ayant plusieurs rôles (usager, instructeur, administrateur) peuvent désormais naviguer entre leurs personas tout en restant dans le contexte actuel (même dossier ou démarche) lorsque c'est possible.

### Fonctionnement
- **Usager → Instructeur** : Si l'usager consulte un dossier et est instructeur de cette procédure, il arrive directement sur la page d'instruction du dossier
- **Instructeur → Usager** : Si l'instructeur consulte un de ses propres dossiers, il arrive directement sur la page usager du dossier
- **Administrateur → Instructeur** : Si l'administrateur consulte une démarche dont il est instructeur, il arrive sur la page d'instruction
- **Instructeur → Administrateur** : Si l'instructeur est administrateur de la procédure, il arrive sur la page d'administration

### Configuration
- Feature flag par utilisateur via Flipper : `:contextual_persona_navigation`
- Activation : `Flipper.enable(:contextual_persona_navigation, user)`
- Fallback automatique vers le comportement standard si les permissions ne permettent pas l'accès contextuel

### Fichiers modifiés
- `app/views/layouts/_account_dropdown.haml` : Ajout de la logique conditionnelle (modifications minimales commentées avec `# pf:`)
- `app/controllers/application_controller.rb` : Include du concern

### Nouveaux fichiers
- `app/controllers/concerns/contextual_navigation_concern.rb` : Logique principale
- `app/helpers/contextual_navigation_helper.rb` : Helpers pour les vues
- `spec/controllers/concerns/contextual_navigation_concern_spec.rb` : Tests
- `spec/system/contextual_persona_navigation_spec.rb` : Tests d'intégration
```

## Points critiques de sécurité

### 1. Validation des permissions
- **OBLIGATOIRE** : Vérifier les permissions avant chaque redirection contextuelle
- Ne jamais faire confiance aux paramètres sans validation
- Utiliser les méthodes Pundit existantes si possible

### 2. Prévention des boucles de redirection
- Ajouter un paramètre `skip_contextual=true` au fallback
- Détecter et logger les tentatives de boucle
- Limite de 2 redirections maximum

### 3. Gestion des erreurs
```ruby
def safe_contextual_redirect(target_profile)
  contextual_redirect_path_for_profile(target_profile)
rescue StandardError => e
  Rails.logger.error "[ContextualNav] Failed: #{e.message}"
  nil # Retour au comportement par défaut
end
```

## Tests requis

### 1. Tests du concern (NOUVEAU FICHIER)
```ruby
# spec/controllers/concerns/contextual_navigation_concern_spec.rb
# pf: tests pour la navigation contextuelle entre personas
RSpec.describe ContextualNavigationConcern, type: :controller do
  controller(ApplicationController) do
    include ContextualNavigationConcern
  end

  describe '#contextual_persona_enabled?' do
    context 'when feature is enabled for user' do
      before { Flipper.enable(:contextual_persona_navigation, user) }
      # Tests...
    end
  end
end
```

### 2. Tests d'intégration avec feature flag
```ruby
# spec/system/contextual_persona_navigation_spec.rb
# pf: tests d'intégration pour la navigation contextuelle entre personas
RSpec.describe "Contextual persona navigation", type: :system do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  
  context "when feature is enabled for specific user" do
    before do
      Flipper.enable(:contextual_persona_navigation, user)
    end
    
    it "uses contextual navigation for enabled user" do
      # Test du comportement contextuel
    end
  end
  
  context "when feature is disabled" do
    it "uses default navigation for other users" do
      login_as other_user
      # Test du comportement par défaut
    end
  end
end
```

## Risques liés au fork et mitigations

### 1. Conflits de merge
- **Risque** : Modifications upstream du dropdown
- **Mitigation** : 
  - Changement minimal (1 ligne conditionnelle par lien)
  - Documentation claire avec `# pf:`
  - Test de non-régression

### 2. Évolution du système de navigation upstream
- **Risque** : Refonte complète du système
- **Mitigation** : 
  - Isolation dans des concerns
  - Feature flag pour désactivation rapide
  - Architecture découplée

## Configuration et monitoring

### Feature flag avec Flipper
```ruby
# Activation progressive
Flipper.enable_percentage_of_actors(:contextual_persona_navigation, 10) # 10% des users

# Activation pour un groupe
Flipper.enable_group(:contextual_persona_navigation, :beta_testers)

# Monitoring
Rails.logger.info "[ContextualNav] Enabled for user: #{current_user.id}" if contextual_persona_enabled?
```

### Métriques à suivre
```ruby
# Dans le concern
def track_contextual_navigation(from_profile, to_profile, success)
  Rails.logger.info "[ContextualNav] Transition: #{from_profile} -> #{to_profile}, Success: #{success}, User: #{current_user.id}"
  
  # Si vous avez un système de métriques
  # StatsD.increment("contextual_navigation.transition", tags: ["from:#{from_profile}", "to:#{to_profile}", "success:#{success}"])
end
```

## Checklist de développement

### Phase 1 : Infrastructure
- [ ] Créer le concern `ContextualNavigationConcern`
- [ ] Créer le helper `ContextualNavigationHelper`
- [ ] Configurer Flipper pour la feature
- [ ] Ajouter les includes nécessaires dans ApplicationController

### Phase 2 : Implémentation
- [ ] Implémenter la détection du contexte
- [ ] Implémenter les vérifications de permissions
- [ ] Implémenter la logique de redirection
- [ ] Modifier minimalement le dropdown (commentaires `# pf:`)

### Phase 3 : Tests
- [ ] Tests unitaires du concern
- [ ] Tests du helper
- [ ] Tests d'intégration avec feature flag
- [ ] Tests de sécurité

### Phase 4 : Documentation
- [ ] Mettre à jour `french_polynesia.md`
- [ ] Documenter tous les commentaires `# pf:`
- [ ] Créer un guide utilisateur

### Phase 5 : Déploiement
- [ ] Activer pour les utilisateurs de test
- [ ] Monitorer les logs et métriques
- [ ] Documenter les retours utilisateurs
- [ ] Plan de rollout progressif

## Commandes utiles
```bash
# Gestion du feature flag
rails c
Flipper.enable(:contextual_persona_navigation, User.find_by(email: 'test@example.com'))
Flipper.enabled?(:contextual_persona_navigation, User.first)
Flipper.features

# Tests ciblés
bundle exec rspec spec/controllers/concerns/contextual_navigation_concern_spec.rb
bundle exec rspec spec/system/contextual_persona_navigation_spec.rb

# Vérifier l'impact minimal
git diff --stat # Devrait montrer peu de modifications sur les fichiers existants
git grep "# pf:" # Lister toutes les modifications PF
```

## Notes critiques pour le fork

1. **Upstream first** : Toujours penser à la compatibilité avec les futures mises à jour upstream

2. **Isolation maximale** : Les nouvelles fonctionnalités doivent être dans des fichiers séparés

3. **Documentation des modifications** : Chaque modification d'un fichier existant doit être commentée avec `# pf:`

4. **Rollback facile** : Le feature flag permet de désactiver instantanément en cas de problème

5. **Monitoring actif** : Logger toutes les utilisations pour détecter rapidement les problèmes

6. **Maintenance de french_polynesia.md** : Documenter systématiquement toutes les divergences avec upstream