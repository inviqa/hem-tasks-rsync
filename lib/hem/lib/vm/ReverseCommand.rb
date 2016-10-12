#!/usr/bin/env ruby
# ^ Syntax hint

module Hem
  module Lib
    module Vm
      class ReverseCommand < Command
        def to_s
          require 'tempfile'

          config = ::Tempfile.new 'hem_ssh_config'
          config.write @@vm_inspector.ssh_config
          config.close

          psuedo_tty = opts[:psuedo_tty] ? '-t' : ''

          ssh_command = [
              'ssh',
              "-F #{config.path.shellescape}",
              psuedo_tty
          ].reject { |c| c.empty? }.join(' ')

          pwd_set_command = "cd #{@opts[:pwd].shellescape}; exec /bin/bash"

          vm_command = [
              @pipe_in_vm.nil? ? nil : @pipe_in_vm.gsub(/(\\+)/, '\\\\\1'),
              @command
          ].compact.join(' | ')

          command = [
              pwd_set_command,
              vm_command.empty? ? nil : (vm_command % ssh_command).shellescape
          ].compact.join(' -c ') + @opts[:append].shellescape

          [
              @pipe,
              command
          ].compact.join(' | ')
        end
      end
    end
  end
end
