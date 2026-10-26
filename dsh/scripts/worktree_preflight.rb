#!/usr/bin/env ruby
# frozen_string_literal: true

# Read-only Git worktree preflight.
#
# Ported verbatim in behaviour from
# ~/.codex/skills/codex-session-orchestration/scripts/worktree_preflight.rb.
#
# DSH difference: `subagent` has no worktree/isolation parameter, so the verdict
# no longer selects a transport-level environment. It decides whether the
# dispatch prompt must instruct the child to create an isolated worktree
# (isolated=true) or to work in place with Git writes forbidden (isolated=false).
#
# Only read-only git commands run: rev-parse, symbolic-ref, rev-list, show-ref,
# worktree list. This script never writes to the repository.

require "json"
require "open3"

module DshMainControl
  class WorktreePreflight
    def initialize(project_root)
      @project_root = File.expand_path(project_root.to_s.dup.force_encoding(Encoding::UTF_8))
    end

    def call
      inside = git("rev-parse", "--is-inside-work-tree")
      unless inside[:success] && inside[:stdout] == "true"
        return result(
          is_inside_work_tree: false,
          head_state: "not_git_work_tree",
          reasons: ["not_git_work_tree"]
        )
      end

      head = git("rev-parse", "--verify", "HEAD^{commit}")
      branch = git("symbolic-ref", "--quiet", "--short", "HEAD")
      commit_count = git("rev-list", "--all", "--count")
      worktree_list = git("worktree", "list", "--porcelain")

      head_valid = head[:success] && !head[:stdout].empty?
      branch_name = branch[:success] ? branch[:stdout] : nil
      branch_ref = branch_name && "refs/heads/#{branch_name}"
      branch_ref_exists = branch_ref ? git("show-ref", "--verify", "--quiet", branch_ref)[:success] : false
      commits = commit_count[:success] ? commit_count[:stdout].to_i : nil
      worktree_supported = worktree_list[:success]

      head_state =
        if branch_name
          if head_valid && branch_ref_exists
            "branch"
          elsif commits == 0
            "unborn"
          else
            "invalid"
          end
        elsif head_valid
          "detached"
        else
          "invalid"
        end

      reasons = []
      reasons << "missing_initial_commit" if commits == 0
      reasons << "unborn_branch" if head_state == "unborn"
      reasons << "head_commit_invalid" unless head_valid
      reasons << "missing_branch_ref" if branch_name && !branch_ref_exists
      reasons << "detached_head" if head_state == "detached"
      reasons << "git_worktree_unavailable" unless worktree_supported

      isolated = head_valid && head_state == "branch" && branch_ref_exists && worktree_supported

      result(
        is_inside_work_tree: true,
        head_valid: head_valid,
        head_commit: head_valid ? head[:stdout] : nil,
        head_state: head_state,
        branch: branch_name,
        branch_ref: branch_ref,
        branch_ref_exists: branch_ref_exists,
        commit_count: commits,
        worktree_supported: worktree_supported,
        safe_for_worktree: isolated,
        isolated: isolated,
        prompt_instruction: isolated ? "require_isolated_worktree" : "work_in_place_no_git_writes",
        reasons: reasons
      )
    end

    private

    def git(*arguments)
      stdout, stderr, status = Open3.capture3("git", "-C", @project_root, *arguments)
      {
        success: status.success?,
        stdout: stdout.strip,
        stderr: stderr.strip
      }
    rescue Errno::ENOENT => error
      {
        success: false,
        stdout: "",
        stderr: error.message
      }
    end

    def result(overrides)
      {
        project_root: @project_root,
        is_inside_work_tree: false,
        head_valid: false,
        head_commit: nil,
        head_state: "invalid",
        branch: nil,
        branch_ref: nil,
        branch_ref_exists: false,
        commit_count: nil,
        worktree_supported: false,
        safe_for_worktree: false,
        isolated: false,
        prompt_instruction: "work_in_place_no_git_writes",
        reasons: []
      }.merge(overrides)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  project_root = ARGV[0] || Dir.pwd
  puts JSON.generate(DshMainControl::WorktreePreflight.new(project_root).call)
end
