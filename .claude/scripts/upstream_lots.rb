#!/usr/bin/env ruby
# frozen_string_literal: true

# Planificateur de lots d'intégration upstream.
#
# Découpe la suite des releases upstream non intégrées en « lots » déployables d'un coup,
# en coupant aux barrières :
#   - données  : une MT de backfill/fix doit avoir tourné en prod avant une migration ultérieure
#                (contrainte, suppression) qui touche la même table/colonne ;
#   - déploiement : colonne ignorée (ignored_columns) puis supprimée — les deux dans le même lot
#                exposent les anciens pods pendant le rolling update ;
#   - risque   : release massive (conversion HAML→ERB…) isolée dans son propre lot ;
#   - volume   : budget de conflits par lot, calé sur une session de 2 h. Les conflits sont
#                simulés sans toucher au dépôt : on synthétise « la référence PF déjà intégrée
#                jusqu'à la release précédant le lot » (git merge-tree + commit-tree, conflits
#                antérieurs laissés tels quels), puis on y merge le tag de fin de lot.
#                Hors fichiers régénérés (Gemfile.lock, locales, schémas).
#
# Le plan est précis pour les prochains lots et indicatif au-delà : le relancer après chaque
# lot mergé dans devpf (la base avance, les résolutions réelles remplacent la simulation).
#
# Lecture seule : n'utilise que git (et gh pour les notes de release, en cache) ; les objets
# créés par les simulations vont dans un répertoire temporaire, rien n'est écrit dans le dépôt.
#
# Usage :
#   ruby .claude/scripts/upstream_lots.rb [--base TAG] [--until TAG] [--budget N]
#                                         [--pf-ref REF] [--json FICHIER] [--no-notes]

require 'json'
require 'optparse'
require 'open3'
require 'fileutils'
require 'set'
require 'tmpdir'

TAG_RE = /\A20\d{2}-\d{2}-\d{2}-\d{2}\z/
UPSTREAM_REPO = 'demarches-simplifiees/demarches-simplifiees.fr'
CACHE_DIR = File.expand_path('~/.cache/mes-demarches/upstream-releases')

# Fichiers régénérés ou résolus mécaniquement : exclus de la surface de conflit
GENERATED = [
  %r{\AGemfile\.lock\z}, %r{\Abun\.lock\z}, %r{\Apackage-lock\.json\z}, %r{\Adb/schema\.rb\z},
  %r{\Aapp/graphql/schema\.graphql\z}, %r{\Aapp/graphql/schema\.json\z}, %r{\Aconfig/locales/},
]

# Zones à forte surveillance PF (cf. skill upstream-integration)
WATCH_ZONES = {
  'france_connect' => %r{france_connect},
  'omniauth' => %r{omniauth},
  'mailers' => %r{\Aapp/mailers/},
  'formules/champs' => %r{\Aapp/models/(champ|type_de_champ)\.rb|\Aapp/models/concerns/dossier_champs_concern\.rb},
  'locales' => %r{\Aconfig/locales/},
}

# Sujets upstream qui heurtent une spécificité PF connue
PF_TRIPWIRES = {
  'delayed_job' => 'PF fait encore tourner des workers delayed_job (deployment `jobs` du chart)',
  'api_particulier' => 'API Particulier : usage PF à vérifier',
  'openstack' => 'stockage : PF est sur S3, pas openstack',
  'france_connect' => 'FC modifié : vérifier le jumeau OmniAuth (Google/Microsoft/Tatou)',
  'ruby_version' => 'montée de version Ruby : Dockerfile + .ruby-version + CI',
}

CONSTRAINT_OPS = %w[
  change_column_null validate_check_constraint validate_foreign_key add_check_constraint
  remove_column remove_columns rename_column drop_table remove_reference remove_index
]

# Opérations qui ÉCHOUENT si les données n'ont pas été préparées : barrière dure entre la MT et elles.
# Les autres (clé étrangère : PostgreSQL ignore les NULL ; suppressions) ne donnent qu'une alerte.
HARD_OPS = %w[change_column_null add_check_constraint validate_check_constraint unique_index]

Options = Struct.new(:base, :until_tag, :budget, :pf_ref, :json, :notes, keyword_init: true)

def sh(*cmd, allow_fail: false)
  out, err, st = Open3.capture3(*cmd)
  raise "Échec : #{cmd.join(' ')}\n#{err}" if !st.success? && !allow_fail
  st.success? ? out : nil
end

def git(*args, allow_fail: false) = sh('git', *args, allow_fail:)

def parse_options
  opts = Options.new(budget: 15, pf_ref: 'origin/devpf', notes: true)
  OptionParser.new do |o|
    o.banner = 'Usage : upstream_lots.rb [options]'
    o.on('--base TAG', 'Dernière release upstream intégrée (défaut : déduite de --pf-ref)') { opts.base = _1 }
    o.on('--until TAG', 'Dernière release à planifier (défaut : la plus récente)') { opts.until_tag = _1 }
    o.on('--budget N', Integer, 'Conflits max par lot (défaut 15 fichiers)') { opts.budget = _1 }
    o.on('--pf-ref REF', 'Référence PF (défaut origin/devpf)') { opts.pf_ref = _1 }
    o.on('--json FICHIER', 'Écrit aussi le plan en JSON') { opts.json = _1 }
    o.on('--no-notes', 'Ne pas lire les notes de release upstream (gh)') { opts.notes = false }
  end.parse!
  opts
end

# --- Collecte ---------------------------------------------------------------

def upstream_tags(base, until_tag)
  all = git('tag', '-l', '20*').split.grep(TAG_RE).sort
  base ||= all.select { git('merge-base', '--is-ancestor', _1, $opts.pf_ref, allow_fail: true) }.last
  candidates = all.select { _1 > base && (until_tag.nil? || _1 <= until_tag) }
  main = candidates.select { git('merge-base', '--is-ancestor', _1, 'upstream/main', allow_fail: true) }
  skipped = candidates - main
  [base, main, skipped]
end

def added_files(from, to, path)
  git('diff', '--diff-filter=A', '--name-only', from, to, '--', path).split
end

def migration_ops(tag, file)
  src = git('show', "#{tag}:#{file}")
  ops = []
  src.scan(/\b(#{CONSTRAINT_OPS.join('|')})\b\s*\(?\s*:?"?(\w+)"?(?:\s*,\s*:?"?([^,\n]+))?/) do |op, table, arg|
    col = case op
    when 'validate_foreign_key' then "#{singular(arg.to_s[/\w+/].to_s)}_id" # 2e argument = table référencée
    when 'add_check_constraint' then arg.to_s[/(\w+)\s+IS NOT NULL/i, 1]
    when 'validate_check_constraint' then nil # nommée par name:, colonne inconnue
    else arg.to_s[/\w+/]
    end
    ops << { op:, table:, column: col.presence_or_nil }
  end
  ops << { op: 'unique_index', table: src[/add_index\s+:(\w+)/, 1], column: nil } if src.include?('unique: true')
  ops
end

def mt_info(tag, file)
  src = git('show', "#{tag}:#{file}")
  auto = src.lines.any? { _1.match?(/^\s*run_on_first_deploy\b/) }
  commented = src.lines.any? { _1.match?(/^\s*#\s*run_on_first_deploy/) }
  writes = src.match?(/update_all|update!|update_columns|update\(|destroy|delete_all|save!|\.create\b|create!|create_\w+|insert_all|upsert|\.nullify|\.touch/)
  {
    file:, name: File.basename(file, '.rb'),
    run_on_deploy: auto ? 'auto' : (commented ? 'commenté' : 'absent'),
    writes:,
    tokens: src.scan(/\b[A-Z][A-Za-z]+(?:::[A-Z][A-Za-z]+)*\b|\b[a-z_]{4,}\b/).uniq,
  }
end

def release_notes(tag)
  return nil unless $opts.notes
  FileUtils.mkdir_p(CACHE_DIR)
  cache = File.join(CACHE_DIR, "#{tag}.md")
  return File.read(cache) if File.exist?(cache)
  body = sh('gh', 'release', 'view', tag, '--repo', UPSTREAM_REPO, '--json', 'body', '--jq', '.body', allow_fail: true)
  File.write(cache, body || '') if body
  body
end

def generated?(file) = GENERATED.any? { file.match?(_1) }

def singular(word) = word.sub(/ies\z/, 'y').sub(/(ss)\z/, '\\1').sub(/s\z/, '')

def camel(str) = str.split('_').map(&:capitalize).join

# Noms de modèle plausibles pour une table : singulier du dernier mot, ou de chaque mot (types_de_champ → TypeDeChamp)
def model_candidates(table)
  words = table.split('_')
  [
    camel((words[0..-2] + [singular(words.last)]).join('_')),
    camel(words.map { singular(_1) }.join('_')),
  ].uniq
end

# git merge-tree renvoie 1 quand il y a des conflits : on lit la sortie quel que soit le code
def merge_tree(*args)
  out, err, st = Open3.capture3('git', 'merge-tree', '--write-tree', '--no-messages', *args)
  raise "merge-tree #{args.join(' ')} : #{err}" if st.exitstatus > 1
  out.lines.map(&:strip).reject(&:empty?)
end

# Commit synthétique « référence PF + upstream jusqu'à `tag` », mémoïsé
def synthetic_pf(tag)
  return $opts.pf_ref if tag == $base
  ($synthetic ||= {})[tag] ||= begin
    tree = merge_tree("--merge-base=#{$base}", $opts.pf_ref, tag).first
    sh('git', 'commit-tree', tree, '-p', $opts.pf_ref, '-p', tag, '-m', "simulation #{tag}").strip
  end
end

def collect(prev, tag, pf_divergence)
  files = git('diff', '--name-only', prev, tag).split
  shortstat = git('diff', '--shortstat', prev, tag)
  lines = shortstat.scan(/(\d+) (?:insertion|deletion)/).flatten.sum(&:to_i)
  overlap = files.select { pf_divergence.include?(_1) }.reject { generated?(_1) }
  deleted = git('diff', '--diff-filter=D', '--name-only', prev, tag).split
  haml_deleted_files = deleted.select { _1.end_with?('.haml') }
  migrations = added_files(prev, tag, 'db/migrate').map { { file: _1, ops: migration_ops(tag, _1) } }
  mts = added_files(prev, tag, 'app/tasks/maintenance').grep_v(/concerns/).map { mt_info(tag, _1) }
  model_diff = git('diff', prev, tag, '--', 'app/models')
  ignored = model_diff.lines.grep(/^\+.*ignored_columns/).flat_map { _1.scan(/["':](\w+)/).flatten }
  notes = release_notes(tag)
  tripwires = []
  tripwires << 'delayed_job' if files.any? { _1.include?('delayed_job') } || migrations.any? { _1[:file].include?('delayed_job') }
  tripwires << 'api_particulier' if migrations.any? { _1[:file].include?('api_particulier') }
  tripwires << 'openstack' if mts.any? { _1[:name].include?('openstack') }
  tripwires << 'france_connect' if files.any? { _1.match?(%r{\Aapp/(controllers|services|models|views)/.*france_connect}) }
  tripwires << 'ruby_version' if files.include?('.ruby-version')
  {
    tag:, prev:, files: files.size, lines:, overlap:, haml_deleted: haml_deleted_files.size, haml_deleted_files:,
    zones: WATCH_ZONES.select { |_, re| files.any? { _1.match?(re) } }.keys,
    gems: files.include?('Gemfile.lock'),
    migrations:, mts:, ignored_columns: ignored.uniq, tripwires:,
    notes_mt: notes&.lines&.grep(/maintenance|tâche|task|backfill|manuel/i)&.map(&:strip) || [],
  }
end

# --- Barrières --------------------------------------------------------------

class String
  def presence_or_nil = empty? ? nil : self
end

class NilClass
  def presence_or_nil = nil
end

# Une MT de lot précédent « alimente » une migration si elle cite sa table/son modèle ET sa colonne
def data_dependency(mt, op)
  return false unless mt[:writes] && op[:table]
  models = model_candidates(op[:table])
  cites_table = mt[:tokens].any? { |t| t == op[:table] || models.any? { t == _1 || t.end_with?("::#{_1}") } }
  cites_col = op[:column].nil? || mt[:tokens].include?(op[:column])
  cites_table && cites_col
end

def barrier_before(lot, rel)
  reasons = []
  rel[:migrations].each do |m|
    m[:ops].each do |op|
      lot.each do |prev|
        prev[:mts].each do |mt|
          next unless HARD_OPS.include?(op[:op]) && data_dependency(mt, op)
          reasons << { kind: 'données', detail: "MT #{mt[:name]} (#{prev[:tag]}) avant #{op[:op]} #{op[:table]}#{op[:column] && ".#{op[:column]}"} (#{File.basename(m[:file])})" }
        end
        if %w[remove_column remove_columns rename_column].include?(op[:op]) && op[:column] && prev[:ignored_columns].include?(op[:column])
          reasons << { kind: 'déploiement', detail: "#{op[:table]}.#{op[:column]} ignorée en #{prev[:tag]} puis supprimée (#{File.basename(m[:file])})" }
        end
      end
    end
  end
  reasons.uniq
end

# Dépendances MT → migration à l'intérieur d'un lot (même release ou releases groupées)
def lot_warnings(rels)
  rels.each_with_index.flat_map do |rel, i|
    rel[:migrations].flat_map do |m|
      m[:ops].flat_map do |op|
        rels[0..i].flat_map { |src| src[:mts].map { [src, _1] } }.select { |_, mt| data_dependency(mt, op) }.map do |src, mt|
          target = "#{op[:op]} #{op[:table]}#{op[:column] && ".#{op[:column]}"} (#{File.basename(m[:file])}, #{rel[:tag]})"
          if HARD_OPS.include?(op[:op])
            "🔴 MT `#{mt[:name]}` (#{src[:tag]}) doit tourner AVANT #{target} : backfill à intégrer à la migration (issue C) ou lot à couper"
          else
            "MT `#{mt[:name]}` (#{src[:tag]}) liée à #{target} : vérifier l'ordre (non bloquant)"
          end
        end
      end
    end
  end.uniq
end

# Vues PF à réécrire : fichiers HAML modifiés côté PF et supprimés (convertis en ERB) par upstream dans le lot
def haml_rewrites(rels)
  deleted = rels.flat_map { _1[:haml_deleted_files] }.to_set
  lot_conflicts(rels).select { deleted.include?(_1) }
end

# Conflits prévus pour un lot : merge du tag de fin dans la référence PF simulée à jour de la release précédente
def lot_conflicts(rels)
  key = [rels.first[:prev], rels.last[:tag]]
  ($lot_conflicts ||= {})[key] ||= begin
    files = merge_tree("--name-only", "--merge-base=#{key[0]}", synthetic_pf(key[0]), key[1]).drop(1)
    files.reject { generated?(_1) }.to_set
  end
end

# Coût d'un lot : conflits prévus, les réécritures de vue HAML→ERB comptant double
def lot_cost(rels) = lot_conflicts(rels).size + haml_rewrites(rels).size

def heavy?(rel) = lot_cost([rel]) > $opts.budget

# --- Découpage glouton ------------------------------------------------------

def plan(releases)
  lots = []
  current = []
  cost = 0
  close = ->(reason) { lots << { releases: current, cost:, closed_by: reason } unless current.empty?; current = []; cost = 0 }
  releases.each do |rel|
    if heavy?(rel)
      close.call({ kind: 'risque', detail: "#{rel[:tag]} isolée (coût #{lot_cost([rel])})" })
      current = [rel]
      cost = lot_cost([rel])
      close.call({ kind: 'risque', detail: 'release lourde à elle seule : lot à part, prévoir plusieurs sessions' })
      next
    end
    barriers = barrier_before(current, rel)
    if barriers.any?
      close.call(barriers.first.merge(others: barriers.drop(1)))
    elsif current.any? && (with_rel = lot_cost(current + [rel])) > $opts.budget
      close.call({ kind: 'volume', detail: "budget #{$opts.budget} dépassé avec #{rel[:tag]} (coût #{with_rel})" })
    end
    current << rel
    cost = lot_cost(current)
  end
  close.call({ kind: 'fin', detail: 'dernière release planifiée' })
  lots
end

# --- Rendu ------------------------------------------------------------------

def render(base, skipped, lots)
  total = lots.sum { _1[:releases].size }
  out = +"# Plan de lots upstream\n\n"
  out << "Base intégrée : **#{base}** — #{total} releases à intégrer en **#{lots.size} lots** (budget #{$opts.budget} conflits par lot, simulés contre #{$opts.pf_ref}).\n"
  out << "Ignorées (hors upstream/main, hotfix) : #{skipped.join(', ')}\n" if skipped.any?
  out << "\nCoût = conflits prévus + vues HAML→ERB à réécrire (qui comptent donc double).\n"
  out << "\n| Lot | Releases | Nb | Coût | Conflits | Vues HAML | Migr. | MT (auto/à décider) | Alertes | Coupé par |\n|---|---|---|---|---|---|---|---|---|---|\n"
  lots.each_with_index do |lot, i|
    rs = lot[:releases]
    mts = rs.flat_map { _1[:mts] }
    auto = mts.count { _1[:run_on_deploy] == 'auto' }
    range = rs.size == 1 ? rs.first[:tag] : "#{rs.first[:tag]} → #{rs.last[:tag]}"
    warnings = lot_warnings(rs)
    alerts = warnings.count { _1.start_with?('🔴') }.then { |h| [h.positive? ? "🔴#{h}" : nil, rs.flat_map { _1[:tripwires] }.uniq.map { |t| t.split('_').first }].flatten.compact.join(' ') }
    out << "| #{i + 1} | #{range} | #{rs.size} | #{lot[:cost]} | #{lot_conflicts(rs).size} | #{haml_rewrites(rs).size} | #{rs.sum { _1[:migrations].size }} | #{auto}/#{mts.size - auto} | #{alerts} | #{lot[:closed_by][:kind]} |\n"
  end
  lots.each_with_index do |lot, i|
    rs = lot[:releases]
    out << "\n## Lot #{i + 1} — #{rs.first[:tag]}#{rs.size > 1 ? " → #{rs.last[:tag]}" : ''}\n\n"
    out << "- Releases : #{rs.map { _1[:tag] }.join(', ')}\n"
    out << "- Volume : #{rs.sum { _1[:files] }} fichiers, #{rs.sum { _1[:lines] }} lignes ; coût #{lot[:cost]} (#{lot_conflicts(rs).size} conflits dont #{haml_rewrites(rs).size} vues HAML à réécrire en ERB)\n"
    conflicts = lot_conflicts(rs).to_a.sort
    out << "- Conflits : #{conflicts.first(12).map { "`#{_1}`" }.join(', ')}#{conflicts.size > 12 ? " … (+#{conflicts.size - 12})" : ''}\n" if conflicts.any?
    zones = rs.flat_map { _1[:zones] }.uniq
    out << "- Zones surveillées : #{zones.join(', ')}\n" if zones.any?
    out << "- Gems modifiées : oui\n" if rs.any? { _1[:gems] }
    rs.flat_map { _1[:tripwires] }.uniq.each { out << "- ⚠️ PF : #{PF_TRIPWIRES[_1]}\n" }
    rs.each do |r|
      r[:migrations].select { _1[:ops].any? }.each do |m|
        out << "- Migration à risque (#{r[:tag]}) : `#{File.basename(m[:file])}` — #{m[:ops].map { |o| [o[:op], o[:table], o[:column]].compact.join(' ') }.uniq.join(' ; ')}\n"
      end
      r[:mts].each do |mt|
        out << "- MT (#{r[:tag]}) : `#{mt[:name]}` — run_on_first_deploy #{mt[:run_on_deploy]}#{mt[:writes] ? ', écrit des données' : ''}\n"
      end
      r[:notes_mt].first(3).each { out << "- Note upstream (#{r[:tag]}) : #{_1[0, 160]}\n" }
    end
    lot_warnings(rs).each { out << "- ⚠️ #{_1}\n" }
    cb = lot[:closed_by]
    out << "- **Coupé par (#{cb[:kind]})** : #{cb[:detail]}\n"
    Array(cb[:others]).each { out << "  - aussi : #{_1[:detail]}\n" }
  end
  out
end

# --- Main -------------------------------------------------------------------

$opts = parse_options

# merge-tree --write-tree et commit-tree écrivent des objets : on les isole dans un répertoire
# temporaire (le dépôt reste lisible en « alternate ») pour ne laisser aucun objet orphelin.
repo_objects = File.expand_path(git('rev-parse', '--git-path', 'objects').strip)
tmp_objects = Dir.mktmpdir('upstream-lots-objects')
ENV['GIT_OBJECT_DIRECTORY'] = tmp_objects
ENV['GIT_ALTERNATE_OBJECT_DIRECTORIES'] = repo_objects
at_exit { FileUtils.rm_rf(tmp_objects) }
base, tags, skipped = upstream_tags($opts.base, $opts.until_tag)
$base = base
abort "Aucune release à planifier après #{base}" if tags.empty?
pf_divergence = git('diff', '--name-only', base, $opts.pf_ref).split.to_set
warn "Collecte de #{tags.size} releases depuis #{base}…"
releases = ([base] + tags).each_cons(2).map { |prev, tag| collect(prev, tag, pf_divergence) }
lots = plan(releases)
puts render(base, skipped, lots)
if $opts.json
  serializable = lots.map { |l| l.merge(conflicts: lot_conflicts(l[:releases]).to_a.sort, releases: l[:releases].map { _1.except(:mts).merge(mts: _1[:mts].map { |m| m.except(:tokens) }) }) }
  File.write($opts.json, JSON.pretty_generate(base:, skipped:, lots: serializable))
end
