# frozen_string_literal: true

# pf: ces specs ne testent pas du code, ils testent une discipline.
# Leur rôle est de faire échouer la CI au prochain merge upstream plutôt que de
# laisser une régression de libellé partir en production.
# Clés qui désignent l'identifiant d'entreprise sans savoir de quel référentiel
# il relève : elles doivent mentionner les deux. Défini hors du bloc describe
# pour ne pas déclencher Lint/ConstantDefinitionInBlock.
CLES_TERMINOLOGIE_ENTREPRISE = [
  'activerecord.attributes.siret',
  'activerecord.attributes.siret_siege_social',
  'activerecord.attributes.user.siret',
  'activerecord.attributes.service.siret',
  'activemodel.models.siret',
].freeze

describe 'Terminologie de l’identifiant d’entreprise' do
  describe 'chaque clé sensible mentionne les deux référentiels' do
    CLES_TERMINOLOGIE_ENTREPRISE.each do |cle|
      it "#{cle} mentionne Tahiti et SIRET" do
        valeur = I18n.t(cle, locale: :fr)

        expect(valeur).to be_a(String), "#{cle} n’existe pas ou n’est pas une chaîne"
        expect(valeur).to match(/Tahiti/i),
          "#{cle} = #{valeur.inspect} — upstream a probablement réintroduit « SIRET » seul"
        expect(valeur).to match(/SIRET/i),
          "#{cle} = #{valeur.inspect} — le SIRET métropolitain doit être mentionné"
      end
    end
  end

  # Une surcharge dans custom_locales cesse silencieusement de s'appliquer si
  # upstream renomme ou supprime la clé d'origine. Ce test la transforme en
  # échec explicite.
  describe 'aucune surcharge orpheline dans custom_locales' do
    # Le backend I18n de l'application fusionne config/locales ET custom_locales :
    # y chercher une clé la trouverait toujours, puisque la surcharge l'y a mise.
    # Il faut donc un backend neuf chargé du seul amont pour que le garde détecte
    # réellement une clé qu'upstream a renommée ou supprimée.
    let(:traductions_amont) do
      backend = I18n::Backend::Simple.new
      Rails.root.glob('config/locales/**/*.yml').each { |f| backend.load_translations(f) }
      backend.send(:translations)
    end

    def chemins_de_cles(hash, prefixe = [])
      hash.flat_map do |cle, valeur|
        chemin = prefixe + [cle.to_s]
        valeur.is_a?(Hash) ? chemins_de_cles(valeur, chemin) : [chemin]
      end
    end

    Rails.root.glob('config/custom_locales/**/*.yml').each do |fichier|
      context File.basename(fichier) do
        it 'ne surcharge que des clés existant dans config/locales' do
          contenu = YAML.load_file(fichier)

          contenu.each do |locale, arbre|
            chemins_de_cles(arbre).each do |chemin|
              cle = chemin.join('.')
              valeur_amont = chemin.reduce(traductions_amont[locale.to_sym]) do |noeud, segment|
                noeud.is_a?(Hash) ? noeud[segment.to_sym] : nil
              end

              expect(valeur_amont).not_to be_nil,
                "#{cle} (#{locale}) est surchargée mais n’existe plus en amont — " \
                'upstream l’a probablement renommée ou supprimée, la surcharge ne s’applique plus'
            end
          end
        end
      end
    end
  end
end
