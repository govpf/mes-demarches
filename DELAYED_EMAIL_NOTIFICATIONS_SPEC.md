# Spécifications : Envoi d'emails différés pour réduire le spam

## 🎯 Objectif

Réduire le nombre d'emails envoyés aux usagers en différant l'envoi de certains emails si l'état du dossier change rapidement.

## 📋 Contexte

### Problème actuel
- Les usagers reçoivent trop d'emails pour chaque dossier
- Pour les démarches rapides : email brouillon + email dépôt en quelques minutes
- Pour les instructions rapides : email instruction + email clôture en quelques minutes

### Solution implémentée (généralisée à toutes les procédures)
Différer l'envoi de certains emails pour éviter le spam :
1. **Email brouillon** : différé de `estimation_durée × 3` minutes (minimum 5 minutes)
2. **Email instruction** : différé de `15 minutes` (constante fixe)

**Important** : Cette fonctionnalité est désormais active pour **toutes les procédures**, sans feature flag.

## 🚀 User Stories

### US1 : Email brouillon différé
**En tant qu'** usager  
**Je veux** ne pas recevoir d'email brouillon si je dépose mon dossier rapidement  
**Afin de** réduire le nombre d'emails reçus  

**Critères d'acceptation :**
- Si je crée un dossier et le dépose avant `estimation_durée * 2`, je ne reçois que l'email de dépôt
- Si je crée un dossier et ne le dépose pas avant `estimation_durée * 2`, je reçois l'email brouillon
- L'email est toujours enregistré dans la messagerie du dossier

### US2 : Email instruction différé
**En tant qu'** usager  
**Je veux** ne pas recevoir d'email d'instruction si mon dossier est clôturé rapidement  
**Afin de** réduire le nombre d'emails reçus  

**Critères d'acceptation :**
- Si mon dossier passe en instruction et est clôturé avant 15 minutes, je ne reçois que l'email de clôture
- Si mon dossier reste en instruction plus de 15 minutes, je reçois l'email d'instruction
- L'email est toujours enregistré dans la messagerie du dossier

## 🔧 Architecture technique

### Constantes (sans variables d'environnement)
```ruby
# Dans app/jobs/draft_notification_job.rb
DRAFT_NOTIFICATION_DELAY_MULTIPLIER = 3  # Coefficient multiplicateur

# Dans app/jobs/instruction_notification_job.rb
INSTRUCTION_NOTIFICATION_DELAY_MINUTES = 15  # Délai fixe en minutes
```

### Protection contre l'envoi à des dossiers supprimés
Les jobs vérifient maintenant `hidden_by_user_at` avant l'envoi :
```ruby
# pf: condition étendue avec hidden_by_user_at (inspiré de upstream PR #179)
def should_send_notification?(dossier)
  dossier.brouillon? && dossier.hidden_by_user_at.blank?
end
```

### Jobs créés
1. **DraftNotificationJob** : Gère l'envoi différé des emails brouillon
2. **InstructionNotificationJob** : Gère l'envoi différé des emails instruction

### Fichiers modifiés
1. **app/controllers/users/dossiers_controller.rb** : Utilise `DraftNotificationJob` pour tous les dossiers
2. **app/controllers/users/commencer_controller.rb** : Utilise `DraftNotificationJob` pour dossiers pré-remplis
3. **app/models/concerns/dossier_state_concern.rb** : Utilise `InstructionNotificationJob` pour tous les dossiers
4. **app/mailers/dossier_mailer.rb** : Suppression du check `AbortDeliveryError` (géré dans le job)

### Fichiers créés
1. **app/jobs/draft_notification_job.rb** : Job pour emails brouillon avec check `hidden_by_user_at`
2. **app/jobs/instruction_notification_job.rb** : Job pour emails instruction avec check `hidden_by_user_at`
3. **spec/jobs/draft_notification_job_spec.rb** : Tests complets incluant suppression
4. **spec/jobs/instruction_notification_job_spec.rb** : Tests complets incluant suppression

## 📝 Tests unitaires à implémenter

### Test du DraftNotificationJob

```ruby
# spec/jobs/draft_notification_job_spec.rb
describe DraftNotificationJob do
  let(:dossier) { create(:dossier) }
  
  describe '#perform' do
    context 'quand le dossier est toujours en brouillon' do
      it 'envoie l\'email brouillon' do
        expect(DossierMailer).to receive(:notify_new_draft)
          .with(dossier)
          .and_return(double(deliver_now: true))
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier est passé en construction' do
      it 'n\'envoie pas l\'email brouillon' do
        dossier.en_construction!
        
        expect(DossierMailer).not_to receive(:notify_new_draft)
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier n\'existe plus' do
      it 'ne lève pas d\'erreur' do
        expect { described_class.new.perform(999999) }.not_to raise_error
      end
    end
  end
end
```

### Test du InstructionNotificationJob

```ruby
# spec/jobs/instruction_notification_job_spec.rb
describe InstructionNotificationJob do
  let(:dossier) { create(:dossier, :en_instruction) }
  
  describe '#perform' do
    context 'quand le dossier est toujours en instruction' do
      it 'envoie l\'email instruction' do
        expect(NotificationMailer).to receive(:send_en_instruction_notification)
          .with(dossier)
          .and_return(double(deliver_now: true))
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier est accepté' do
      it 'n\'envoie pas l\'email instruction' do
        dossier.accepte!
        
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier est refusé' do
      it 'n\'envoie pas l\'email instruction' do
        dossier.refuse!
        
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)
        
        described_class.new.perform(dossier.id)
      end
    end
    
    context 'quand le dossier est classé sans suite' do
      it 'n\'envoie pas l\'email instruction' do
        dossier.classer_sans_suite!
        
        expect(NotificationMailer).not_to receive(:send_en_instruction_notification)
        
        described_class.new.perform(dossier.id)
      end
    end
  end
end
```

### Test des contrôleurs

```ruby
# spec/controllers/users/dossiers_controller_spec.rb
describe 'POST #create' do
  it 'programme l\'envoi différé de l\'email brouillon' do
    procedure = create(:procedure, :published)
    
    expect(DraftNotificationJob).to receive(:set)
      .with(wait: anything)
      .and_return(double(perform_later: true))
    
    post :create, params: { procedure_id: procedure.id }
  end
  
  it 'calcule le bon délai basé sur l\'estimation' do
    procedure = create(:procedure, :published)
    # Supposons une estimation de 300 secondes (5 minutes)
    allow_any_instance_of(ProcedureRevision).to receive(:estimated_fill_duration).and_return(300)
    
    expected_delay = (300 / 60.0 * 2).round # 10 minutes
    
    expect(DraftNotificationJob).to receive(:set)
      .with(wait: expected_delay.minutes)
      .and_return(double(perform_later: true))
    
    post :create, params: { procedure_id: procedure.id }
  end
end
```

### Test des modèles

```ruby
# spec/models/dossier_spec.rb
describe 'passage en instruction' do
  it 'programme l\'envoi différé de l\'email instruction' do
    dossier = create(:dossier, :en_construction)
    instructeur = create(:instructeur)
    
    expect(InstructionNotificationJob).to receive(:set)
      .with(wait: 15.minutes)
      .and_return(double(perform_later: true))
    
    dossier.passer_en_instruction!(instructeur: instructeur)
  end
end
```

### Tests d'intégration

```ruby
# spec/system/delayed_emails_spec.rb
describe 'Envoi d\'emails différés', type: :system do
  let(:user) { create(:user) }
  let(:procedure) { create(:procedure, :published) }
  
  scenario 'dossier rapide - pas d\'email brouillon' do
    # Simuler une estimation de 5 minutes
    allow_any_instance_of(ProcedureRevision).to receive(:estimated_fill_duration).and_return(300)
    
    # Créer un dossier
    login_as(user, scope: :user)
    visit new_dossier_path(procedure_id: procedure.id)
    
    # Le déposer rapidement (avant 10 minutes)
    perform_enqueued_jobs(only: DraftNotificationJob) do
      # Simuler le passage rapide en construction
      dossier = user.dossiers.last
      dossier.en_construction!
      
      # Avancer le temps de 10 minutes
      travel 10.minutes
    end
    
    # Vérifier qu'aucun email brouillon n'est envoyé
    expect(ActionMailer::Base.deliveries.count).to eq(1) # Seulement l'email de dépôt
  end
  
  scenario 'instruction rapide - pas d\'email instruction' do
    dossier = create(:dossier, :en_construction)
    instructeur = create(:instructeur)
    
    perform_enqueued_jobs(only: InstructionNotificationJob) do
      # Passer en instruction
      dossier.passer_en_instruction!(instructeur: instructeur)
      
      # Clôturer rapidement
      dossier.accepter!(instructeur: instructeur, motivation: 'OK')
      
      # Avancer le temps de 15 minutes
      travel 15.minutes
    end
    
    # Vérifier qu'aucun email instruction n'est envoyé
    # Seulement l'email d'acceptation
    expect(ActionMailer::Base.deliveries.count).to eq(1)
  end
end
```

## 📊 Implémentation étape par étape

### Étape 1 : Créer les jobs
1. Créer `app/jobs/draft_notification_job.rb`
2. Créer `app/jobs/instruction_notification_job.rb`
3. Écrire les tests unitaires pour les jobs

### Étape 2 : Modifier les contrôleurs
1. Modifier `app/controllers/users/dossiers_controller.rb`
2. Modifier `app/controllers/users/commencer_controller.rb`
3. Remplacer `deliver_later` par `DraftNotificationJob.set(...).perform_later`

### Étape 3 : Modifier les modèles
1. Modifier `app/models/concerns/dossier_state_concern.rb`
2. Remplacer l'envoi immédiat par `InstructionNotificationJob.set(...).perform_later`

### Étape 4 : Tests complets
1. Écrire tous les tests unitaires
2. Écrire les tests d'intégration
3. Tester les cas limites

### Étape 5 : Validation
1. Tester en local avec des dossiers réels
2. Vérifier que les emails sont bien dans la messagerie
3. Valider les délais avec différentes estimations

## 🚨 Points d'attention pour développeur junior

### Erreurs à éviter
1. **Ne pas oublier** de vérifier l'état du dossier dans les jobs
2. **Gérer les exceptions** si le dossier n'existe plus
3. **Tester tous les états** : brouillon, construction, instruction, accepté, refusé, sans suite
4. **Vérifier** que les emails restent dans la messagerie même s'ils ne sont pas envoyés

### Bonnes pratiques
1. **Toujours tester** avec des données réelles
2. **Logs utiles** pour débugger les jobs
3. **Gestion d'erreurs** robuste
4. **Tests complets** de tous les scénarios

### Debugging
- Vérifier les jobs programmés : `rails console` puis `Sidekiq::ScheduledSet.new`
- Logs des jobs : chercher dans `log/development.log`
- Tester les jobs manuellement : `DraftNotificationJob.perform_now(dossier_id)`

---

## 📊 Déploiement

### État actuel (2025-02)
- ✅ **Généralisé à toutes les procédures** (feature flag supprimé)
- ✅ Protection contre dossiers supprimés (`hidden_by_user_at`)
- ✅ Tests complets avec cas limites
- ✅ Intégration avec upstream PR #179

### Constantes configurées
- **Coefficient brouillon** : `3` (estimation × 3, minimum 5 minutes)
- **Délai instruction** : `15 minutes`

Ces valeurs peuvent être ajustées dans les fichiers de job selon les retours terrain.

### Rollback si nécessaire
Pour revenir au système immédiat, modifier les contrôleurs :
```ruby
# Remplacer
DraftNotificationJob.schedule_for_dossier(dossier)
# Par
DossierMailer.with(dossier:).notify_new_draft.deliver_later
```