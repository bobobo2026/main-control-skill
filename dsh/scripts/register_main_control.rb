#!/usr/bin/env ruby
# frozen_string_literal: true

# Bind (or unbind) the current DSH session as a project's main control.
#
# Codex equivalent: the original skill asked the model to hand-edit
# ~/.codex/project-main-controls.json with $CODEX_THREAD_ID. DSH has a real
# session id in $DSH_SESSION_ID, so binding is scripted here to keep the
# registry syntactically valid and to avoid hand-edited JSON drift.
#
# Usage:
#   ruby register_main_control.rb [project_root] [--name "项目名"]
#                                                  [--auto-create|--no-auto-create]
#                                                  [--allow-missing-root]
#   ruby register_main_control.rb --unbind [project_root]
#   ruby register_main_control.rb --list
#
# Writes ~/.dsh/project-main-controls.json atomically and keeps one .bak copy.

require "json"

UTF8 = Encoding::UTF_8
REGISTRY = File.expand_path("~/.dsh/project-main-controls.json")
SCHEMA_VERSION = 1

def force_utf8(value)
  value.to_s.dup.force_encoding(UTF8)
end

def today
  Time.now.strftime("%Y-%m-%d")
end

def load_registry
  return { "version" => SCHEMA_VERSION, "projects" => [] } unless File.file?(REGISTRY)

  raw = File.read(REGISTRY, encoding: UTF8)
  parsed = JSON.parse(raw)
  parsed = { "version" => SCHEMA_VERSION, "projects" => [] } unless parsed.is_a?(Hash)
  parsed["version"] ||= SCHEMA_VERSION
  parsed["projects"] = [] unless parsed["projects"].is_a?(Array)
  parsed
end

def save_registry(registry)
  directory = File.dirname(REGISTRY)
  Dir.mkdir(directory) unless Dir.exist?(directory)
  backup = "#{REGISTRY}.bak"
  File.write(backup, File.read(REGISTRY, encoding: UTF8), mode: "w", encoding: UTF8) if File.file?(REGISTRY)
  temporary = "#{REGISTRY}.tmp.#{Process.pid}"
  File.write(temporary, JSON.pretty_generate(registry) + "\n", mode: "w", encoding: UTF8)
  File.rename(temporary, REGISTRY)
end

def entry_root(entry)
  File.expand_path(force_utf8(entry["root"]))
end

def session_id
  force_utf8(ENV.fetch("DSH_SESSION_ID", ""))
end

# --- argument parsing -------------------------------------------------------

argv = ARGV.map { |value| force_utf8(value) }
list_only = argv.delete("--list")
unbind = argv.delete("--unbind")
allow_missing_root = !argv.delete("--allow-missing-root").nil?
auto_create = if argv.delete("--auto-create")
                true
              elsif argv.delete("--no-auto-create")
                false
              end
name_index = argv.index("--name")
name = name_index ? argv.delete_at(name_index + 1) : nil
argv.delete_at(name_index) if name_index
root_argument = argv.reject { |value| value.start_with?("--") }.first

# --- --list -----------------------------------------------------------------

if list_only
  registry = load_registry
  current = session_id
  rows = registry["projects"].map do |entry|
    bound = force_utf8(entry["main_session_id"] || entry["main_thread_id"] || "")
    {
      project: force_utf8(entry["project"]),
      root: entry_root(entry),
      enabled: entry.fetch("enabled", true),
      auto_create_execution_threads: entry["auto_create_execution_threads"] == true,
      main_session_id: bound,
      is_current_session: !current.empty? && bound == current
    }
  end
  puts JSON.pretty_generate(
    registry: REGISTRY,
    current_session_id: current,
    project_count: rows.length,
    bound_count: rows.count { |row| !row[:main_session_id].to_s.empty? },
    projects: rows
  )
  exit 0
end

# --- bind / unbind ----------------------------------------------------------

root = File.expand_path(root_argument || Dir.pwd)
current = session_id

if !unbind && current.empty?
  warn "DSH_SESSION_ID is empty; refusing to bind an unidentified session."
  exit 1
end

# A typo'd root would bind nothing yet look successful, because role detection
# can never match a cwd underneath it.
if !unbind && !allow_missing_root && !File.directory?(root)
  warn "root does not exist: #{root}"
  warn "refusing to bind; pass --allow-missing-root to register it anyway."
  exit 1
end

registry = load_registry
exact = registry["projects"].find { |entry| entry_root(entry) == root }
parents = registry["projects"].select do |entry|
  candidate = entry_root(entry)
  candidate != root && root.start_with?(candidate + File::SEPARATOR)
end

if unbind
  if exact.nil?
    puts JSON.generate(unbound: false, reason: "no_entry_for_root", root: root)
    exit 0
  end
  previous = force_utf8(exact["main_session_id"] || exact["main_thread_id"] || "")
  exact.delete("main_thread_id")
  exact["main_session_id"] = ""
  exact["updated_at"] = today
  save_registry(registry)
  puts JSON.generate(unbound: true, project: force_utf8(exact["project"]), root: root,
                     previous_main_session_id: previous, updated_at: exact["updated_at"])
  exit 0
end

entry =
  if exact
    exact
  else
    created = {
      "project" => force_utf8(name || File.basename(root)),
      "root" => root,
      "main_session_id" => "",
      "enabled" => true,
      "updated_at" => today
    }
    registry["projects"] << created
    created
  end

entry["project"] = force_utf8(name) if name && !name.empty?
entry["root"] = root
entry.delete("main_thread_id")
previous = force_utf8(entry["main_session_id"] || "")
entry["main_session_id"] = current
entry["enabled"] = entry.fetch("enabled", true)
entry["auto_create_execution_threads"] = auto_create unless auto_create.nil?
entry["updated_at"] = today

save_registry(registry)

puts JSON.generate(
  registered: true,
  project: entry["project"],
  root: root,
  main_session_id: current,
  previous_main_session_id: previous,
  auto_create_execution_threads: entry["auto_create_execution_threads"] == true,
  enabled: entry["enabled"],
  updated_at: entry["updated_at"],
  registry: REGISTRY,
  shadowed_parent_entries: parents.map { |item| force_utf8(item["project"]) }
)
