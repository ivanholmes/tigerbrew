# Gets a patch from a GitHub commit or pull request and applies it to Homebrew.
# Optionally, installs it too.

require 'utils'
require 'formula'

module Homebrew
  def tap arg
    match = arg.match(%r[homebrew-([\w-]+)/])
    match[1].downcase if match
  end

  def pull_url url
    # GitHub provides commits/pull-requests raw patches using this URL.
    url += '.patch'

    patchpath = HOMEBREW_CACHE + File.basename(url)
    curl url, '-o', patchpath

    ohai 'Applying patch'
    patch_args = []
    # Normally we don't want whitespace errors, but squashing them can break
    # patches so an option is provided to skip this step.
    if ARGV.include? '--ignore-whitespace' or ARGV.include? '--clean'
      patch_args << '--whitespace=nowarn'
    else
      patch_args << '--whitespace=fix'
    end

    # Fall back to three-way merge if patch does not apply cleanly
    patch_args << "-3"
    patch_args << patchpath

    begin
      safe_system 'git', 'am', *patch_args
    rescue ErrorDuringExecution
      if ARGV.include? "--resolve"
        odie "Patch failed to apply: try to resolve it."
      else
        system 'git', 'am', '--abort'
        odie 'Patch failed to apply: aborted.'
      end
    ensure
      patchpath.unlink
    end
  end

  def pull
    if ARGV.empty?
      onoe 'This command requires at least one argument containing a URL or pull request number'
    end

    if ARGV[0] == '--rebase'
      onoe 'You meant `git pull --rebase`.'
    end

    ARGV.named.each do |arg|
      if arg.to_i > 0
        url = 'https://github.com/mistydemeo/tigerbrew/pull/' + arg
        issue = arg
      else
        url_match = arg.match HOMEBREW_PULL_OR_COMMIT_URL_REGEX
        unless url_match
          ohai 'Ignoring URL:', "Not a GitHub pull request or commit: #{arg}"
          next
        end

        url = url_match[0]
        issue = url_match[3]
      end

      if ARGV.include?("--bottle") && issue.nil?
        raise "No pull request detected!"
      end

      if tap_name = tap(url)
        user = url_match[1].downcase
        tap_dir = HOMEBREW_REPOSITORY/"Library/Taps/#{user}/homebrew-#{tap_name}"
        safe_system "brew", "tap", "#{user}/#{tap_name}" unless tap_dir.exist?
        Dir.chdir tap_dir
      else
        Dir.chdir HOMEBREW_REPOSITORY
      end

      # The cache directory seems like a good place to put patches.
      HOMEBREW_CACHE.mkpath

      # Store current revision and branch
      revision = `git rev-parse --short HEAD`.strip
      branch = `git symbolic-ref --short HEAD`.strip

      pull_url url

      changed_formulae = []

      if tap_dir
        formula_dir = %w[Formula HomebrewFormula].find { |d| tap_dir.join(d).directory? } || ""
      else
        formula_dir = "Library/Formula"
      end

      Utils.popen_read(
        "git", "diff-tree", "-r", "--name-only",
        "--diff-filter=AM", revision, "HEAD", "--", formula_dir
      ).each_line do |line|
        name = File.basename(line.chomp, ".rb")

        begin
          changed_formulae << Formula[name]
        # Make sure we catch syntax errors.
        rescue Exception => e
          next
        end
      end

      unless ARGV.include? '--bottle'
        changed_formulae.each do |f|
          next unless f.bottle
          opoo "#{f.name} has a bottle: do you need to update it with --bottle?"
        end
      end

      if issue && !ARGV.include?('--clean')
        ohai "Patch closes issue ##{issue}"
        message = `git log HEAD^.. --format=%B`

        if ARGV.include? '--bump'
          odie 'Can only bump one changed formula' unless changed_formulae.length == 1
          f = changed_formulae.first
          subject = "#{f.name} #{f.version}"
          ohai "New bump commit subject: #{subject}"
          message = "#{subject}\n\n#{message}"
        end

        # If this is a pull request, append a close message.
        unless message.include? "Closes ##{issue}."
          message += "\nCloses ##{issue}."
          safe_system 'git', 'commit', '--amend', '--signoff', '--allow-empty', '-q', '-m', message
        end
      end

      if ARGV.include? "--bottle"
        bottle_branch = "pull-bottle-#{issue}"
        safe_system "git", "checkout", "-B", bottle_branch, revision
        if tap_name
          pull_url "https://github.com/BrewTestBot/homebrew-#{tap_name}/compare/homebrew:master...pr-#{issue}"
        else
          pull_url "https://github.com/BrewTestBot/homebrew/compare/homebrew:master...pr-#{issue}"
        end
        safe_system "git", "rebase", branch
        safe_system "git", "checkout", branch
        safe_system "git", "merge", "--ff-only", "--no-edit", bottle_branch
        safe_system "git", "branch", "-D", bottle_branch
      end

      ohai 'Patch changed:'
      safe_system "git", "diff-tree", "-r", "--stat", revision, "HEAD"

      if ARGV.include? '--install'
        changed_formulae.each do |f|
          ohai "Installing #{f.name}"
          install = f.installed? ? 'upgrade' : 'install'
          safe_system 'brew', install, '--debug', f.name
        end
      end
    end
  end
end
