# frozen_string_literal: true

RSpec.describe Types::File do
  describe "#url" do
    # `new` est protected sur les Types GraphQL → on l'instancie via send pour tester le résolveur seul
    subject(:resolved_url) { described_class.send(:new, object, nil).url }

    context "when the object is an ActiveStorage attachment (S3 presigned)" do
      let(:object) { double("attachment") }

      before { allow(object).to receive(:is_a?).with(Hash).and_return(false) }

      # pf: régression — passer host: faisait planter aws-sdk en prod S3
      # (ArgumentError: unexpected value at params[:host]). L'URL presignée est absolue,
      # aucun host à transmettre. cf. upstream #12346 / 3871d37538.
      it "n'envoie pas host: au service de stockage" do
        expect(object).to receive(:url).with(no_args).and_return("https://storage.example/presigned")

        expect(resolved_url).to eq("https://storage.example/presigned")
      end
    end

    context "when the object is a Hash" do
      let(:object) { { url: "https://example/from-hash" } }

      it "retourne l'url portée par le hash" do
        expect(resolved_url).to eq("https://example/from-hash")
      end
    end
  end
end
