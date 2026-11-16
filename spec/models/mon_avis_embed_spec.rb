# frozen_string_literal: true

RSpec.describe MonAvisEmbed do
  describe '#link_href' do
    subject { described_class.new(embed).link_href("site") }

    context 'when embed is blank' do
      let(:embed) { nil }
      it { is_expected.to be_nil }
    end

    context 'when embed has no link' do
      let(:embed) { '<img src="https://jedonnemonavis.numerique.gouv.fr/static/bouton-bleu-clair.svg" />' }
      it { is_expected.to be_nil }
    end

    context 'with a valid embed (nd_source rewritten)' do
      let(:embed) do
        '<a href="https://jedonnemonavis.numerique.gouv.fr/Demarches/123?nd_source=button&key=abc"><img src="https://jedonnemonavis.numerique.gouv.fr/static/bouton-bleu-clair.svg" alt="Je donne mon avis" /></a>'
      end
      it { is_expected.to eq("https://jedonnemonavis.numerique.gouv.fr/Demarches/123?nd_source=site&key=abc") }
    end

    context 'with a new-design href (no nd_source param)' do
      let(:embed) do
        '<a href="https://jedonnemonavis.numerique.gouv.fr/Demarches/4079?button=4509"><img src="https://jedonnemonavis.numerique.gouv.fr/static/bouton-bleu-sombre.svg" /></a>'
      end
      it { is_expected.to eq("https://jedonnemonavis.numerique.gouv.fr/Demarches/4079?button=4509") }
    end

    context 'with an untrusted domain (defense in depth)' do
      let(:embed) { '<a href="https://evil.com/phishing?nd_source=button"><img src="https://jedonnemonavis.numerique.gouv.fr/x.png" /></a>' }
      it { is_expected.to be_nil }
    end

    context 'with a non-https scheme' do
      let(:embed) { '<a href="http://jedonnemonavis.numerique.gouv.fr/Demarches/1"><img src="https://jedonnemonavis.numerique.gouv.fr/x.png" /></a>' }
      it { is_expected.to be_nil }
    end

    context 'with the legacy monavis domain' do
      let(:embed) { '<a href="https://monavis.numerique.gouv.fr/Demarches/9?nd_source=button&key=z"><img src="https://monavis.numerique.gouv.fr/monavis-static/bouton-bleu.png" /></a>' }
      it { is_expected.to eq("https://monavis.numerique.gouv.fr/Demarches/9?nd_source=site&key=z") }
    end
  end
end
