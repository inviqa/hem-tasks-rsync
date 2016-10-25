#!/usr/bin/env ruby
# ^ Syntax hint

after 'deps:composer', 'deps:sync:vendor_directory'

after 'vm:reload', 'deps:composer_preload'
after 'vm:start', 'deps:composer_preload'
after 'deps:composer', 'deps:composer_preload'

namespace :deps do
  desc 'Update composer dependencies'
  argument :packages, optional: true, default: {}, as: Array
  task :composer_update do |_task_name, args|
    next unless File.exist? File.join(Hem.project_path, 'composer.json')

    Rake::Task['tools:composer'].invoke

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

            complete = true
          rescue Hem::ExternalCommandError
            Hem.ui.warning 'Updating composer dependencies locally failed!'
          end
        end
      end

      run(*args) unless complete

      Rake::Task['deps:sync:vendor_directory'].execute

      Hem.ui.success 'Composer dependencies updated'
    end

    Hem.ui.separator
  end

  desc 'Preload the composer files into file system cache'
  task :composer_preload do
    Hem.ui.title 'Composer PHP files loading into file system cache'
    command = <<-COMMAND
        if [ -e vendor ]; then \
          find vendor -type f -name "*.php" -exec cat {} > /dev/null + ; \
        fi
        COMMAND
    run command, realtime: true
    Hem.ui.success 'Composer PHP files loaded into file system cache'
  end

  desc 'Syncing dependencies to/from the VM'
  namespace :sync do
    desc 'Syncing vendor directory changes, in either direction'
    task :vendor_directory do
      Hem.ui.title 'Syncing vendor directory changes'

      Rake::Task['vm:sync_guest_changes'].execute(
        from_path: 'vendor/',
        to_path: 'vendor',
        deciding_file_path: File.join('vendor', 'autoload.php')
      )

      Hem.ui.success 'Synced vendor directory changes'
      Hem.ui.separator
    end

    desc 'Download the vendor directory from the guest to the host'
    task :vendor_directory_from_guest do
      Hem.ui.title 'Downloading vendor directory changes from guest'

      Rake::Task['vm:sync_guest_changes'].execute(
        from_path: 'vendor/',
        to_path: 'vendor'
      )

      Hem.ui.success('Downloaded vendor directory changes from guest')
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
  end
end
