#!/usr/bin/env ruby
# frozen_string_literal: true

# DSH main-control role detection.
#
# Ported from ~/.codex/skills/codex-session-orchestration/scripts/main_control_role.rb.
# Differences from the Codex original:
#   - reads ~/.dsh/project-main-controls.json instead of the Codex registry
#   - compares $DSH_SESSION_ID instead of $CODEX_THREAD_ID
#   - forces UTF-8 on the config and on ARGV, so it survives a US-ASCII locale
#     (the Codex original raises Encoding::InvalidByteSequenceError when LANG is
#     unset and the registry contains non-ASCII project names or emoji)
#   - accepts legacy "main_thread_id" in addition to "main_session_id"

require "json"

UTF8 = Encoding::UTF_8

def force_utf8(value)
  value.to_s.dup.force_encoding(UTF8)
end

config_path = File.expand_path("~/.dsh/project-main-controls.json")
cwd = File.expand_path(force_utf8(ARGV[0] || Dir.pwd))
session_id = force_utf8(ENV.fetch("DSH_SESSION_ID", ""))

def emit(payload)
  puts JSON.generate(payload)
end

def unconfigured(cwd, session_id, reason)
  emit(
    configured: false,
    role: "unconfigured",
    auto_create_execution_threads: false,
    cwd: cwd,
    session_id: session_id,
    reason: reason
  )
  exit 0
end

unconfigured(cwd, session_id, "missing_registry") unless File.file?(config_path)

begin
  raw = File.read(config_path, encoding: UTF8)
  config = JSON.parse(raw)
rescue JSON::ParserError, Encoding::InvalidByteSequenceError => error
  unconfigured(cwd, session_id, "invalid_registry: #{error.class}")
end

projects = Array(config.is_a?(Hash) ? config["projects"] : nil)
         .select { |project| project.is_a?(Hash) && project.fetch("enabled", true) }

match = projects
        .select do |project|
          root = File.expand_path(force_utf8(project["root"]))
          cwd == root || cwd.start_with?(root + File::SEPARATOR)
        end
        .max_by { |project| File.expand_path(force_utf8(project["root"])).length }

unconfigured(cwd, session_id, "no_project_match") unless match

# Longest path prefix wins so a parent project can cover backend, frontend,
# miniapp and worktrees beneath it.
root = File.expand_path(force_utf8(match["root"]))
main_session_id = force_utf8(match["main_session_id"] || match["main_thread_id"] || "")

role =
  if !session_id.empty? && session_id == main_session_id
    "main_control"
  else
    "execution"
  end

emit(
  configured: true,
  role: role,
  auto_create_execution_threads: match["auto_create_execution_threads"] == true,
  project: force_utf8(match["project"]),
  root: root,
  main_session_id: main_session_id,
  session_id: session_id
)
