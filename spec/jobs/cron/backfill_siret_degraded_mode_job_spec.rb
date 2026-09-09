# frozen_string_literal: true

RSpec.describe Cron::BackfillSiretDegradedModeJob, type: :job do
  describe '.perform' do
    # pf: SIRET valide au sens de Luhn — le routage vers EtablissementAdapter passe
    # désormais par IdentifiantEntreprise#siret?, qui vérifie la clé de contrôle.
    let(:etablissement) { create(:etablissement, adresse: nil, siret: '41816609600051') }
    let(:new_adresse) { '7 rue du puits, coye la foret' }

    context 'fix etablissement with dossier with adresse nil' do
      let(:dossier) { create(:dossier, :en_construction, etablissement: etablissement) }
      before do
        dossier
      end
      it 'works' do
        allow_any_instance_of(APIEntreprise::EtablissementAdapter).to receive(:to_params).and_return({ adresse: new_adresse })
        expect { Cron::BackfillSiretDegradedModeJob.perform_now }.to change { etablissement.reload.adresse }.from(nil).to(new_adresse)
      end
    end

    context 'fix etablisEtablissementAdapter.newsement with champs with adresse nil' do
      let(:procedure) { create(:procedure, :published, types_de_champ_public:) }
      let(:types_de_champ_public) { [{ type: :siret }] }
      let(:dossier) { create(:dossier, :with_populated_champs, procedure:) }
      let(:champ_siret) { dossier.champs.first }

      before do
        champ_siret
        champ_siret.update_column(:etablissement_id, etablissement.id)
      end
      it 'works' do
        allow_any_instance_of(APIEntreprise::EtablissementAdapter).to receive(:to_params).and_return({ adresse: new_adresse })
        expect { Cron::BackfillSiretDegradedModeJob.perform_now }.to change { etablissement.reload.adresse }.from(nil).to(new_adresse)
      end
    end

    # pf: update_etablissement_from_degraded_mode applique un double contrôle sur
    # un numéro Tahiti — d'abord la nature du numéro saisi (tahiti?), puis la
    # complétude de ce que l'adapter ISPF a renvoyé (tahiti_complet?). Ce cron
    # est le seul appelant testé de cette méthode : sans ce contexte, le second
    # contrôle n'était exercé par aucun spec.
    context 'fix etablissement with a Tahiti number in degraded mode' do
      let(:etablissement) { create(:etablissement, adresse: nil, siret: 'G33972') }
      let(:dossier) { create(:dossier, :en_construction, etablissement: etablissement) }

      before do
        dossier
      end

      context 'when the adapter resolves a complete Tahiti number' do
        it 'met à jour l’établissement' do
          allow_any_instance_of(APIEntreprise::PfEtablissementAdapter).to receive(:to_params)
            .and_return({ siret: 'G33972001', adresse: new_adresse })
          expect { Cron::BackfillSiretDegradedModeJob.perform_now }.to change { etablissement.reload.adresse }.from(nil).to(new_adresse)
        end
      end

      context 'when the adapter cannot narrow down to a single establishment' do
        # pf: la clé :adresse est déterminante — sans elle, ce test passerait même
        # si le double contrôle (tahiti_complet? sur le retour de l'adapter) était
        # retiré, puisque update!(siret: 'G33972') serait alors un no-op (la valeur
        # est déjà celle de l'établissement) et l'adresse resterait nil de toute façon.
        # En la fournissant, on force : garde-fou actif → return nil avant tout
        # update! → adresse toujours nil (test passe) ; garde-fou retiré → update!
        # écrit l'adresse → le test échoue. Ne pas simplifier ce stub.
        it 'renonce et laisse l’adresse à nil' do
          allow_any_instance_of(APIEntreprise::PfEtablissementAdapter).to receive(:to_params)
            .and_return({ siret: 'G33972', adresse: new_adresse })
          expect { Cron::BackfillSiretDegradedModeJob.perform_now }.not_to change { etablissement.reload.adresse }
        end
      end
    end
  end
end
