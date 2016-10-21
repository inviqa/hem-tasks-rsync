#!/usr/bin/env ruby
# ^ Syntax hint

before 'deps:composer', 'deps:sync:composer_files_to_guest'
after 'deps:composer', 'deps:sync:reload_or_sync'

after 'vm:reload', 'deps:composer_preload'
after 'vm:start', 'deps:composer_preload'
after 'deps:composer', 'deps:composer_preload'

namespace :deps do
  desc 'Update composer dependencies'
  argument :packages, optional: true, default: {}, as: Array
  task :composer_update do |_task_name, args|
    next unless File.exist? File.join(Hem.project_path, 'composer.json')

    Rake::Task['tools:composer'].invoke

    Rake::Task['deps:sync:composer_files_to_guest'].execute

    packages = args[:packages].map(&:shellescape).join(' ')

    Hem.ui.title 'Updating composer dependencies'
    Dir.chdir Hem.project_path do
      ansi = Hem.ui.supports_color? ? '--ansi' : ''
      args = ["php bin/composer.phar update #{packages} #{ansi} --prefer-dist", { realtime: true, indent: 2 }]
      complete = false

      unless maybe(Hem.project_config.tasks.deps.composer.disable_host_run)
        check = Hem::Lib::HostCheck.check(filter: /php_present/)

        if check[:php_present] == :ok
          begin
            shell(*args)

            Rake::Task['deps:sync:composer_files_to_guest'].execute
            Rake::Task['vm:rsync_mount_sync'].execute

            complete = true
          rescue Hem::ExternalCommandError
            Hem.ui.warning 'Updating composer dependencies locally failed!'
          end
        end
      end

      unless complete
        run(*args)

        Rake::Task['deps:sync:composer_files_from_guest'].execute
        Rake::Task['deps:sync:vendor_directory_from_guest'].execute
      end

      Hem.ui.success 'Composer dependencies updated'
    end

    Hem.ui.separator
  end

  desc 'Preload the composer files into file system cache'
  task :composer_preload do
    Hem.ui.title 'Composer PHP files loading into file system cache'
    run 'if [ -e vendor ]; then find vendor -type f -name "*.php" -exec cat {} > /dev/null + ; fi', realtime: true
    Hem.ui.success 'Composer PHP files loaded into file system cache'
  end

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
        host_to_guest_allowed: false
      )
    end

    desc 'Upload the vendor directory from the host to the guest'
    task :vendor_directory_to_guest do
      Hem.ui.title 'Uploading vendor directory changes to guest'

      Rake::Task['vm:rsync_manual'].execute(
        from_path: 'vendor/',
        to_path: 'vendor'
      )

      Hem.ui.success('Uploaded vendor directory changes to guest')
    end

    desc 'Reload the VM to use NFS mounts per directory, or sync rsync mounts if already enabled'
    task :reload_or_sync do
      one_mount_point = run 'grep "/vagrant " /proc/mounts || true', capture: true
      if one_mount_point != ''
        Rake::Task['vm:reload'].execute
        Rake::Task['vm:provision_shell'].execute
        Rake::Task['vm:upload_root_files_to_guest'].execute
      else
        Rake::Task['deps:sync:vendor_directory_from_guest'].execute
        Rake::Task['vm:rsync_mount_sync'].execute
      end
    end
  end
end
