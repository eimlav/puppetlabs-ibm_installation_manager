require 'beaker-pe'
require 'beaker-puppet'
require 'beaker-rspec'
require 'beaker/puppet_install_helper'

run_puppet_install_helper
configure_type_defaults_on(hosts)

RSpec.configure do |c|
  module_root = File.expand_path(File.join(File.dirname(__FILE__), '..'))

  c.formatter = :documentation

  # Determine install zip files location
  # Defaults to a Puppet Labs internal repository, to run this externally
  # you must specify a directory on the host or url with the necessary files:
  #  - agent.installer.linux.gtk.x86_64_1.6.2000.20130301_2248.zip
  #  - was.repo.8550.liberty.ndtrial.zip
  # are located.
  # To specify a directory you can use:
  #     "file:///directory/of/the/zips"
  # To specify a url:
  #     "http://path.of/zip_files"
  #
  INSTALL_FILE_PATH = ENV['IBM_INSTALL_SOURCE'] || 'https://artifactory.delivery.puppetlabs.net/artifactory/list/generic/module_ci_resources/modules/ibm_installation_manager'

  # Configure all nodes in nodeset
  c.before :suite do
    # install module
    puppet_module_install(source: module_root, module_name: 'ibm_installation_manager')

    _install_pkg_path = "#{module_root}/spec/fixtures/modules/spec_files/files"
    hosts.each do |host|
      on host, puppet('module', 'install', 'puppetlabs-stdlib'), acceptable_exit_codes: [0, 1]
      on host, puppet('module', 'install', 'puppet-archive'), acceptable_exit_codes: [0, 1]

      # Retrieve the install files for tests.
      pp = <<-EOS
        archive { '/tmp/agent.installer.linux.gtk.x86_64_1.8.7000.20170706_2137.zip':
          source       => "#{INSTALL_FILE_PATH}/agent.installer.linux.gtk.x86_64_1.8.7000.20170706_2137.zip",
          extract      => false,
          extract_path => '/tmp',
        }

        package { 'unzip':
          ensure => present,
          before => Archive['/tmp/ndtrial/was.repo.8550.liberty.ndtrial.zip'],
        }

        file { '/tmp/ndtrial':
          ensure => directory,
        }

        archive { '/tmp/ndtrial/was.repo.8550.liberty.ndtrial.zip':
          source       => "#{INSTALL_FILE_PATH}/was.repo.8550.liberty.ndtrial.zip",
          extract      => true,
          extract_path => '/tmp/ndtrial',
          creates      => '/tmp/ndtrial/repository.config',
        }
      EOS
      apply_manifest_on(host, pp, catch_failures: true)
    end
  end
end

def idempotent_apply(hosts, manifest, opts = {}, &block)
  block_on hosts, opts do |host|
    file_path = host.tmpfile('apply_manifest.pp')
    create_remote_file(host, file_path, manifest + "\n")

    puppet_apply_opts = { :verbose => nil, 'detailed-exitcodes' => nil }
    on_options = { acceptable_exit_codes: [0, 2] }
    on host, puppet('apply', file_path, puppet_apply_opts), on_options, &block
    puppet_apply_opts2 = { :verbose => nil, 'detailed-exitcodes' => nil }
    on_options2 = { acceptable_exit_codes: [0] }
    on host, puppet('apply', file_path, puppet_apply_opts2), on_options2, &block
  end
end
