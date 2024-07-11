# frozen_string_literal: true

# Cookbook Name:: cerner_splunk
# Recipe:: _install
#
# Performs the installation of the Splunk software via package.

# Interpolation Alias
def nsp
  node['splunk']['package']
end

# Attributes
node.default['splunk']['package']['name'] = "#{nsp['base_name']}-#{nsp['version']}-#{nsp['build']}"
node.default['splunk']['package']['file_suffix'] =
  case node['platform_family']
  when 'rhel', 'fedora'
    if node['kernel']['machine'] == 'x86_64'
      # linux rpms of splunk/UF before 9.0.5 are a differently named package.
      package_version = Gem::Version.new(node['splunk']['package']['version'])
      if package_version >= Gem::Version.new('9.0.5')
        '.x86_64.rpm'
      else
        '-linux-2.6-x86_64.rpm'
      end
    else
      '.i386.rpm'
    end
  when 'debian'
    if node['kernel']['machine'] == 'x86_64'
      '-linux-2.6-amd64.deb'
    else
      '-linux-2.6-intel.deb'
    end
  when 'windows'
    if node['kernel']['machine'] == 'x86_64'
      '-x64-release.msi'
    else
      '-x86-release.msi'
    end
  end
node.default['splunk']['package']['file_name'] = "#{nsp['name']}#{nsp['file_suffix']}"
node.default['splunk']['package']['url'] =
  "#{nsp['base_url']}/#{nsp['download_group']}/releases/#{nsp['version']}/#{nsp['platform']}/#{nsp['file_name']}"
node.default['splunk']['home'] = CernerSplunk.splunk_home(node['platform_family'], node['kernel']['machine'], nsp['base_name'])
node.default['splunk']['cmd'] = CernerSplunk.splunk_command(node)

service = CernerSplunk.splunk_service_name(node['platform_family'], nsp['base_name'], node['splunk']['systemd_unit_file_name'])

manifest_missing = proc { ::Dir.glob("#{node['splunk']['home']}/#{node['splunk']['package']['name']}-*").empty? }

if CernerSplunk.splunk_installed?(node)
  splunk_version_file = File.join CernerSplunk.splunk_home(node['platform_family'], node['kernel']['machine'], node['splunk']['package']['base_name']), 'etc', 'splunk.version'
  # The first line of the file should be "VERSION=x.y.z\n"
  previous_splunk_version = File.readlines(splunk_version_file).first[8..12]
end

include_recipe 'cerner_splunk::_restart_marker'

# Under systemd, starting or restarting the service allows the chef run to continue
# before Splunk is finished initializing.  Need to wait a bit to let it fully start
# before we run any other commands.
chef_sleep 'sleep-45' do
  seconds 45
  action :nothing
  only_if { ::File.exist? node['splunk']['systemd_file_location'] }
end

# Actions
# This service definition is used for ensuring splunk is started during the run and to stop splunk service
splunk_start_command = "#{File.join CernerSplunk.splunk_home(node['platform_family'], node['kernel']['machine'], node['splunk']['package']['base_name']), 'bin', 'splunk'} start"
service 'splunk' do
  service_name service
  action :nothing
  supports status: true, start: true, stop: true
  start_command splunk_start_command if CernerSplunk.use_splunk_start_command? node, previous_splunk_version
  notifies :delete, 'file[splunk-marker]', :immediately
  notifies :sleep, 'chef_sleep[sleep-45]', :immediately
end

# This service definition is used for restarting splunk when the run is over
service 'splunk-restart' do
  service_name service
  action :nothing
  supports status: true, restart: true
  only_if { ::File.exist? CernerSplunk.restart_marker_file }
  notifies :delete, 'file[splunk-marker]', :immediately
  notifies :sleep, 'chef_sleep[sleep-45]', :immediately
end

ruby_block 'splunk-delayed-restart' do
  block { true }
  notifies :restart, 'service[splunk-restart]'
end

splunk_file = "#{Chef::Config[:file_cache_path]}/#{node['splunk']['package']['file_name']}"
package_auth = node['splunk']['package']['authorization']
auth_header = CernerSplunk::DataBag.load(package_auth, secret: Chef::EncryptedDataBagItem.load_secret(node['splunk']['data_bag_secret'])) if package_auth
remote_file splunk_file do
  source node['splunk']['package']['url']
  action :create
  headers('Authorization' => auth_header) if auth_header
  only_if(&manifest_missing)
end

# If this is an upgrade, we should stop splunk before installing the new package
# The vagrant tests timeout trying to stop splunk on the windows box though, so skip windows
# https://docs.splunk.com/Documentation/Forwarder/9.0.2/Forwarder/Upgradetheuniversalforwarder
# https://docs.splunk.com/Documentation/Splunk/9.0.2/Installation/UpgradeonUNIX#Upgrade_Splunk_Enterprise
ruby_block 'upgrade-splunk-stop' do
  block { true }
  notifies :stop, 'service[splunk]', :immediately
  only_if { CernerSplunk.splunk_installed?(node) && node['splunk']['package']['version'] != previous_splunk_version && !platform_family?('windows') }
end

if platform_family? 'rhel', 'fedora', 'amazon'
  rpm_package node['splunk']['package']['base_name'] do
    source splunk_file
    version "#{node['splunk']['package']['version']}-#{node['splunk']['package']['build']}"
    only_if(&manifest_missing)
  end
elsif platform_family? 'debian'
  dpkg_package node['splunk']['package']['base_name'] do
    source splunk_file
    version "#{node['splunk']['package']['version']}-#{node['splunk']['package']['build']}"
    only_if(&manifest_missing)
  end
elsif platform_family? 'windows'
  # installing as the system user by default as Splunk has difficulties with being a limited user
  flags = %(AGREETOLICENSE=Yes SERVICESTARTTYPE=auto LAUNCHSPLUNK=0 INSTALLDIR="#{node['splunk']['home'].tr('/', '\\')}")
  # Use admin credentials from databag for initial setup
  admin_username = auth_header['username']
  admin_password = auth_header['password']
  flags += " SPLUNKPASSWORD=#{admin_password}"
  windows_package node['splunk']['package']['base_name'] do
    source splunk_file
    version "#{node['splunk']['package']['version']}-#{node['splunk']['package']['build']}"
    only_if(&manifest_missing)
    options flags
  end
else
  fail 'unsupported platform'
end

include_recipe 'cerner_splunk::_configure_secret'

# For windows, we accept the license during msi install so the ftr file will never be there.
unless platform_family?('windows')
  run_command = "#{node['splunk']['cmd']} help commands --accept-license --answer-yes --no-prompt"
  # Use the provided username and password for initial setup
  run_command += " --seed-passwd 'changeme'" if Gem::Version.new(nsp['version']) >= Gem::Version.new('7.2.0')

  execute 'splunk-first-run' do
    command run_command
    user node['splunk']['user']
    group node['splunk']['group']
    only_if { File.exist?("#{node['splunk']['home']}/ftr") }
  end

  # Set the admin username and password
  execute 'set-admin-password' do
    command "#{node['splunk']['cmd']} edit user admin -password changeme"
    user node['splunk']['user']
    group node['splunk']['group']
    action :run
  end
end

ruby_block 'read splunk.secret' do
  block do
    node.run_state['cerner_splunk']['splunk.secret'] = ::File.open(::File.join(node['splunk']['home'], 'etc/auth/splunk.secret'), 'r') { |file| file.readline.chomp }
  end
end

directory node['splunk']['external_config_directory'] do
  owner node['splunk']['user']
  group node['splunk']['group']
  mode '0700'
end

# SPL-89640 On upgrades, the permissions of this directory is too restrictive
# preventing proper operation of Platform Instrumentation features.
directory "#{node['splunk']['home']}/var/log/introspection" do
  owner node['splunk']['user']
  group node['splunk']['group']
  mode '0700'
end

file 'splunk_package' do
  path splunk_file
  backup false
  not_if(&manifest_missing)
  action :delete
end

include_recipe 'cerner_splunk::_user_management'

# This gets rid of the change password prompt on first login
file "#{node['splunk']['home']}/etc/.ui_login" do
  action :touch
  not_if { ::File.exist? "#{node['splunk']['home']}/etc/.ui_login" }
end

# Ensure OPTIMISTIC_ABOUT_FILE_LOCKING is set before any restarts
ruby_block 'set-optimistic-about-file-locking' do
  block do
    file_path = "#{node['splunk']['home']}/etc/splunk-launch.conf"
    fe = Chef::Util::FileEdit.new(file_path)
    fe.insert_line_if_no_match(/^OPTIMISTIC_ABOUT_FILE_LOCKING = 1$/, 'OPTIMISTIC_ABOUT_FILE_LOCKING = 1')
    fe.write_file
  end
  not_if { ::File.readlines("#{node['splunk']['home']}/etc/splunk-launch.conf").grep(/^OPTIMISTIC_ABOUT_FILE_LOCKING = 1$/).any? }
  action :run
end

# System file changes should be done after first run, but before we start the server
include_recipe 'cerner_splunk::_configure'

