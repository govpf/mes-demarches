# frozen_string_literal: true

# Proxies de confiance pour ActionDispatch::RemoteIp.
#
# Objectif : que `request.remote_ip` reflète la VRAIE IP cliente, et non l'IP
# de l'edge Cloudflare (ex. 172.64.0.0/13) ni le hop interne du cluster.
# C'est critique pour la restriction réseau des jetons API à durée illimitée
# (ApiToken#forbidden_network?), pour Rack::Attack et pour IPService.
#
# Principe : on remonte la chaîne X-Forwarded-For de la droite vers la gauche en
# ignorant les proxies de confiance ; le premier IP hors de cette liste = client.
# Une valeur forgée par le client se retrouve à gauche → ignorée.
#
# Source unique des CIDR Cloudflare : config/cloudflare_ips.txt
# Mise à jour automatisée : .github/workflows/cloudflare-cidr-drift.yml
# (lecture d'un fichier LOCAL au boot — aucun appel réseau au démarrage).

cloudflare_file = Rails.root.join("config", "cloudflare_ips.txt")

cloudflare_cidrs =
  if File.exist?(cloudflare_file)
    File.readlines(cloudflare_file, chomp: true)
        .map(&:strip)
        .reject { |line| line.empty? || line.start_with?("#") }
        .filter_map { |cidr| IPAddr.new(cidr) rescue nil }
  else
    []
  end

# Hops internes du cluster (svclb klipper SNAT + services). Déjà couverts par les
# ranges privés par défaut, listés explicitement pour la lisibilité.
internal_cidrs = ["10.42.0.0/16", "10.43.0.0/16"].filter_map { |cidr| IPAddr.new(cidr) rescue nil }

Rails.application.config.action_dispatch.trusted_proxies =
  ActionDispatch::RemoteIp::TRUSTED_PROXIES + internal_cidrs + cloudflare_cidrs
