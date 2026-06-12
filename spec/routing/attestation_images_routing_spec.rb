# frozen_string_literal: true

RSpec.describe 'AttestationImages routing', type: :routing do
  # pf: régression sécurité (F1) — le proxy public d'images d'attestation
  # (AttestationImagesController#proxy) exposait tout le stockage Active Storage
  # par énumération de blob_id, sans authentification. Code mort (jamais câblé
  # dans le rendu attestation v2), supprimé. La route ne doit plus exister.
  it "n'expose plus le proxy public d'images d'attestation" do
    expect(get: '/attestation_images/proxy').not_to be_routable
  end
end
