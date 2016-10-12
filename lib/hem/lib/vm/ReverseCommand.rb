#!/usr/bin/env ruby
# ^ Syntax hint

# Hem
module Hem
  # Lib!
  module Lib
    # VM!
    module Vm
      # Place the ssh configuration within a command, using sprintf
      class ReverseCommand < Command
        def to_s
          ssh_config = ssh_config()
          ssh_command = ssh_command(ssh_config)
          pwd_set_command = pwd_set_command()
          vm_command = vm_command()

          [
            @pipe,
            full_command(pwd_set_command, vm_command, ssh_command)
          ].compact.join(' | ')
        end
      end

      private

      def ssh_config
        require 'tempfile'

        config = ::Tempfile.new 'hem_ssh_config'
        config.write @@vm_inspector.ssh_config
        config.close

        config
      end

      def ssh_command(config)
        psuedo_tty = @opts[:psuedo_tty] ? '-t' : ''
        [
          'ssh',
          "-F #{config.path.shellescape}",
          psuedo_tty
        ].reject(&:empty?).join(' ')
      end

      def pwd_set_command
        "cd #{@opts[:pwd].shellescape}; exec /bin/bash"
      end

      def vm_command
        [
          @pipe_in_vm.nil? ? nil : @pipe_in_vm.gsub(/(\\+)/, '\\\\\1'),
          @command
        ].compact.join(' | ')
      end

      def full_command(pwd_set_command, vm_command, ssh_command)
        [
          pwd_set_command,
          vm_command.empty? ? nil : (vm_command % ssh_command).shellescape
        ].compact.join(' -c ') + @opts[:append].shellescape
      end
    end
  end
end
