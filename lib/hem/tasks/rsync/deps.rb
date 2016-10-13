#!/usr/bin/env ruby
# ^ Syntax hint

before 'deps:composer', 'deps:sync:composer_files_to_guest'
after 'deps:composer', 'deps:sync:reload_or_sync'

namespace :deps do
  desc 'Syncing dependencies to/from the VM'
  namespace :sync do
    desc 'Download the composer.json and lock from the guest to the host'
    task :composer_files_from_guest do
      Hem.ui.title 'Downloading composer files to host'

      Rake::Task['vm:rsync_manual'].execute(
        from_path: File.join(Hem.project_config.vm.project_mount_path, 'composer.json'),
        to_path: File.join(Hem.project_path, 'composer.json'),
        is_reverse: true
      )
      Rake::Task['vm:rsync_manual'].execute(
        from_path: File.join(Hem.project_config.vm.project_mount_path, 'composer.lock'),
        to_path: File.join(Hem.project_path, 'composer.lock'),
        is_reverse: true
      )
      Hem.ui.success 'Downloaded composer files to host'
    end

    desc 'Upload the composer.json and lock from the host to the guest'
    task :composer_files_to_guest do
      Hem.ui.title 'Uploading composer files to guest'

      Rake::Task['vm:upload_root_files_to_guest'].invoke

      Hem.ui.success('Uploaded composer files to guest')
    end

    desc 'Download the vendor directory from the guest to the host'
    task :vendor_directory_from_guest do
      Hem.ui.title 'Downloading vendor directory changes from guest'

      Rake::Task['vm:sync_guest_changes'].execute(
        from_path: 'vendor/',
        to_path: 'vendor',
        deciding_file_path: File.join('vendor', 'autoload.php'),
        guest_to_host_allowed: false
      )
    end

    desc 'Reload the VM to use NFS mounts per directory, or sync rsync mounts if already enabled'
    task :reload_or_sync do
      one_mount_point = run 'grep "/vagrant " /proc/mounts || true', capture: true
      if one_mount_point != ''
        Rake::Task['vm:reload'].execute
      else
        Rake::Task['deps:sync:vendor_directory_from_guest'].execute
        Rake::Task['vm:rsync_mount_sync'].execute
      end
    end
  end
end
