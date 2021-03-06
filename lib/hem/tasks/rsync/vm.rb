#!/usr/bin/env ruby
# ^ Syntax hint

after 'vm:reload', 'vm:provision_shell'
after 'vm:start', 'vm:provision_shell'

namespace :vm do
  desc 'Rsync from host to guest, or if in reverse mode, from guest to host'
  argument :from_path
  argument :to_path
  argument 'is_reverse', optional: true, default: false
  task :rsync_manual do |_task_name, args|
    from_path = args[:from_path]
    to_path = args[:to_path]

    Hem.ui.title "Syncing #{from_path} to #{to_path}"

    hostname = 'default'
    if args[:is_reverse]
      # '--delete' deliberately skipped. VM should not delete files from the host OS.
      # Don't want to lose work in case of mistakes
      remote_file_exists = run "if [ -e '#{from_path}' ]; then echo 1; else echo 0; fi", capture: true
      rsync_command = if remote_file_exists == '1'
                        <<-COMMAND
                          rsync --human-readable --compress --archive --rsh='%s' \
                          '#{hostname}:#{from_path}' '#{to_path}'
                          COMMAND
                      else
                        "echo 'Failed to find source file, skipping'"
                      end
    else
      rsync_command = <<-COMMAND
        if [ -e '#{from_path}' ]; then
          rsync --human-readable --compress --archive --rsh='%s' \
          '#{from_path}' '#{hostname}:#{to_path}';
        else
          echo 'Failed to find source file, skipping';
        fi
        COMMAND
    end

    args = [rsync_command, { local: true, realtime: true, indent: 2, on: :host, pwd: Hem.project_path }]
    require_relative File.join('..', '..', 'lib', 'vm', 'ReverseCommand')
    Hem::Lib::Vm::ReverseCommand.new(*args).run

    Hem.ui.success("Synced #{from_path} to #{to_path}")
  end

  desc 'Sync changes from a guest directory to a host directory if a given file is newer'
  argument :from_path
  argument :to_path
  argument :deciding_file_path
  argument :host_to_guest_allowed, optional: true, default: true
  task :sync_guest_changes do |_task_name, args|
    args[:host_to_guest_allowed] = true unless args.key? :host_to_guest_allowed

    Hem.ui.title "Determining if #{args[:deciding_file_path]} is newer on the host or guest"

    local_file_path = File.join(Hem.project_path, args[:deciding_file_path])
    local_file_modified = 0
    local_file_modified = File.mtime(local_file_path).to_i if File.exist? local_file_path

    remote_file_path = File.join(Hem.project_config.vm.project_mount_path, args[:deciding_file_path])
    remote_file_modified = run "if [ -e '#{remote_file_path}' ]; then stat -c \%Y '#{remote_file_path}' ; fi",
                               capture: true

    if local_file_modified.to_i < remote_file_modified.to_i
      Hem.ui.success("Guest file #{args[:deciding_file_path]} is newer, syncing to host")
      from_path = File.join(Hem.project_config.vm.project_mount_path, args[:from_path])
      to_path = File.join(Hem.project_path, args[:to_path])

      Rake::Task['vm:rsync_manual'].execute(
        from_path: from_path,
        to_path: to_path,
        is_reverse: true
      )
    elsif args[:host_to_guest_allowed] && local_file_modified.to_i > remote_file_modified.to_i
      Hem.ui.success("Host file #{args[:deciding_file_path]} is newer, syncing to guest")
      from_path = File.join(Hem.project_path, args[:from_path])
      to_path = File.join(Hem.project_config.vm.project_mount_path, args[:to_path])

      Rake::Task['vm:rsync_manual'].execute(
        from_path: from_path,
        to_path: to_path
      )
    elsif !args[:host_to_guest_allowed]
      Hem.ui.success('Host is more up to date than the guest but syncing via another method')
    else
      Hem.ui.success("Host and guest file #{args[:deciding_file_path]} are up to date, not doing anything")
    end
  end

  desc 'Provision VM via files and shell scripts only'
  task :provision_shell do
    vagrantfile do
      Hem.ui.title 'Provisioning VM via files and shell scripts only'
      vagrant_exec 'provision', '--provision-with', 'shell,file'
      Hem.ui.separator
    end
  end
end
