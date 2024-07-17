# frozen_string_literal: true

# Cookbook Name:: cerner_splunk
# Recipe:: _configure_server
#
# Configures the system server.conf file

require 'json'

hostname = node['hostname']

node_type =
  if hostname.include?('multi') && hostname.include?('master')
    :multi_master
  elsif hostname == 'master'
    :cluster_master
  elsif hostname.include?('node')
    :cluster_slave
  elsif hostname.include?('searchhead')
    :indexer_searchhead
  end

server_stanzas = {
  'general' => {
    'serverName' => node['splunk']['config']['host']
  },
  'sslConfig' => {}
}
execute 'Create a user and restart_splunk' do
    command <<-EOH
      export SPLUNK_HOME=/opt/splunk
      $SPLUNK_HOME/bin/splunk add user admin2 \
        -role admin \
        -password #{node['splunk']['clustering']['admin_password']}
      $SPLUNK_HOME/bin/splunk restart
    EOH
    action :run
  end
# default pass4SymmKey value is 'changeme'
server_stanzas['general']['pass4SymmKey'] = node['splunk']['config']['pass4SymmKey']
# default sslPassword value is 'password'
server_stanzas['sslConfig']['sslPassword'] = node['splunk']['config']['sslPassword']

case node_type
when :forwarder
  server_stanzas['general']['site'] = node['splunk']['forwarder_site']
when :search_head, :shc_search_head, :shc_captain, :server
  clusters = CernerSplunk.all_clusters(node).collect do |(cluster, bag)|
    stanza = "clustermaster:#{cluster}"
    master_uri = bag['master_uri'] || ''
    settings = bag['settings'] || {}
    pass = settings['pass4SymmKey'] || ''

    next if master_uri.empty?

    server_stanzas[stanza] = {}
    server_stanzas[stanza]['master_uri'] = master_uri
    server_stanzas[stanza]['pass4SymmKey'] = pass unless pass.empty?
    if CernerSplunk.multisite_cluster?(bag, cluster)
      server_stanzas[stanza]['multisite'] = true
      server_stanzas[stanza]['site'] = bag['disable_search_affinity'] == true ? 'site0' : bag['site']
    else
      server_stanzas[stanza]['multisite'] = false
    end
    stanza
  end

  clusters.reject!(&:nil?)

  if clusters.any?
    server_stanzas['clustering'] = {}
    server_stanzas['clustering']['mode'] = 'searchhead'
    server_stanzas['clustering']['master_uri'] = clusters.join(',')
  end
when :cluster_master
  admin_password = node['splunk']['clustering']['admin_password']

  execute 'configure_cluster_master' do
    command <<-EOH
      export SPLUNK_HOME=/opt/splunk
      $SPLUNK_HOME/bin/splunk edit cluster-config \\
        -mode master \\
        -replication_factor #{node['splunk']['clustering']['replication_factor']} \\
        -search_factor #{node['splunk']['clustering']['search_factor']} \\
        -secret #{node['splunk']['clustering']['pass4SymmKey']} \\
        -cluster_label #{node['splunk']['clustering']['cluster_label']} \\
        -auth admin2:#{admin_password}
      $SPLUNK_HOME/bin/splunk restart
    EOH
    user 'splunk'
    group 'splunk'
    action :run
  end

when :multi_master
    admin_password = node['splunk']['clustering']['admin_password']
  
    execute 'configure_multi_master' do
      command <<-EOH
        export SPLUNK_HOME=/opt/splunk
        $SPLUNK_HOME/bin/splunk edit cluster-config \\
          -mode manager \\
          -multisite true \\
          -available_sites site1,site2 \\
          -site site1 \\
          -site_replication_factor origin:2,total:3 \\
          -site_search_factor origin:1,total:2 \\
          -secret #{node['splunk']['clustering']['pass4SymmKey']} \\
          -auth admin2:#{admin_password}
        $SPLUNK_HOME/bin/splunk restart
      EOH
      user 'splunk'
      group 'splunk'
      action :run
 end

when :cluster_slave
    admin_password = node['splunk']['clustering']['admin_password']
    pass4SymmKey = node['splunk']['clustering']['pass4SymmKey']
  
    site_argument = if hostname.include?('site1')
                      "-site site1 \\"
                    elsif hostname.include?('site2')
                      "-site site2 \\"
                    else
                      ""
                    end
  
    execute 'configure_cluster_slave' do
      command <<-EOH
        export SPLUNK_HOME=/opt/splunk
        $SPLUNK_HOME/bin/splunk edit cluster-config \\
          -mode peer \\
          #{site_argument}
          -manager_uri https://#{node['splunk']['clustering']['manager_ip']}:8089 \\
          -replication_port #{node['splunk']['clustering']['replication_port']} \\
          -secret #{pass4SymmKey} \\
          -auth admin2:#{admin_password}
        $SPLUNK_HOME/bin/splunk restart
      EOH
      user 'splunk'
      group 'splunk'
      action :run
    end

when :indexer_searchhead
    admin_password = node['splunk']['clustering']['admin_password']
    pass4SymmKey = node['splunk']['clustering']['pass4SymmKey']
  
    site_argument = if hostname.include?('site1')
                      "-site site1 \\"
                    elsif hostname.include?('site2')
                      "-site site2 \\"
                    else
                      ""
                    end
  
    execute 'configure_cluster_slave' do
      command <<-EOH
        export SPLUNK_HOME=/opt/splunk
        $SPLUNK_HOME/bin/splunk edit cluster-config \\
          -mode searchhead \\
          #{site_argument}
          -manager_uri https://#{node['splunk']['clustering']['manager_ip']}:8089 \\
          -secret #{pass4SymmKey} \\
          -auth admin2:#{admin_password}
        $SPLUNK_HOME/bin/splunk restart
      EOH
      user 'splunk'
      group 'splunk'
      action :run
    end



when :shc_deployer
  bag = CernerSplunk.my_cluster_data(node)
  settings = (bag['shc_settings'] || {}).reject do |k, _|
    k.start_with?('_cerner_splunk')
  end
  pass = settings.delete('pass4SymmKey')

  server_stanzas['shclustering'] = settings
  server_stanzas['shclustering']['pass4SymmKey'] = pass if pass
end

if %i[shc_search_head shc_captain].include? node_type
  cluster, bag = CernerSplunk.my_cluster(node)
  deployer_uri = bag['deployer_uri'] || ''
  replication_ports = bag['shc_replication_ports'] || bag['replication_ports'] || {}
  management_host = CernerSplunk.management_host(node)
  settings = (bag['shc_settings'] || {}).reject do |k, _|
    k.start_with?('_cerner_splunk')
  end
  pass = settings.delete('pass4SymmKey')

  fail "Missing deployer URI for #{cluster}" if deployer_uri.empty?
  fail "Missing replication port configuration for cluster '#{cluster}'" if replication_ports.empty?

  replication_ports.each do |port, port_settings|
    ssl = port_settings['_cerner_splunk_ssl'] == true
    stanza = ssl ? "replication_port-ssl://#{port}" : "replication_port://#{port}"
    server_stanzas[stanza] = port_settings.reject do |k, _|
      k.start_with? '_cerner_splunk'
    end
  end

  path = "#{node['splunk']['home']}/etc/system/local/server.conf"
  old_stanzas = CernerSplunk::Conf::Reader.new(path).read if File.exist?(path)
  old_id = (old_stanzas['shclustering'] || {})['id'] if old_stanzas

  server_stanzas['shclustering'] = settings
  server_stanzas['shclustering']['pass4SymmKey'] = pass if pass
  server_stanzas['shclustering']['deployer_uri'] = deployer_uri
  server_stanzas['shclustering']['disabled'] = 0
  server_stanzas['shclustering']['mgmt_uri'] = "https://#{management_host}:8089"
  server_stanzas['shclustering']['id'] = old_id if old_id
end

license_uri =
  case node_type
  when :license_server
    'self'
  when :cluster_master, :cluster_slave, :server, :search_head, :shc_search_head, :shc_captain, :shc_deployer
    if node['splunk']['free_license']
      'self'
    else
      (CernerSplunk.my_cluster_data(node) || {})['license_uri'] || 'self'
    end
  when :forwarder
    if node['splunk']['package']['base_name'] == 'splunk' && node['splunk']['heavy_forwarder']['use_license_uri']
      (CernerSplunk.my_cluster_data(node) || {})['license_uri'] || 'self'
    else
      'self'
    end
  end

license_group =
  case node_type
  when :license_server
    'Enterprise'
  when :cluster_master, :cluster_slave, :shc_search_head, :shc_captain, :shc_deployer
    if license_uri == 'self'
      'Trial'
    else
      'Enterprise'
    end
  when :forwarder
    'Forwarder'
  when :search_head
    if license_uri == 'self'
      'Trial'
    else
      'Forwarder'
    end
  when :server
    if node['splunk']['free_license']
      'Free'
    elsif license_uri == 'self'
      'Trial'
    else
      'Enterprise'
    end
  end

if license_uri == 'self'
  %w[forwarder free enterprise download-trial].each do |group|
    server_stanzas["lmpool:auto_generated_pool_#{group}"] = {
      'description' => "auto_generated_pool_#{group}",
      'quota' => 'MAX',
      'slaves' => '*',
      'stack_id' => group
    }
  end
end

license_pools = CernerSplunk::DataBag.load(node['splunk']['config']['license-pool'], secret: node['splunk']['data_bag_secret'])

if node_type == :license_server && !license_pools.nil?
  auto_generated_pool_size = CernerSplunk.convert_to_bytes license_pools['auto_generated_pool_size']
  server_stanzas['lmpool:auto_generated_pool_enterprise']['quota'] = auto_generated_pool_size
  allotted_pool_size = 0

  license_pools['pools'].each do |pool, pool_config|
    pool_max_size = CernerSplunk.convert_to_bytes pool_config['size']
    server_stanzas["lmpool:#{pool}"] = {
      'description' => pool,
      'quota' => pool_max_size,
      'slaves' => pool_config['GUIDs'].join(','),
      'stack_id' => node.run_state['license_type']
    }
    allotted_pool_size += pool_max_size
  end
  node.run_state['cerner_splunk']['total_allotted_pool_size'] = allotted_pool_size + auto_generated_pool_size
end

server_stanzas['license'] = {
  'master_uri' => license_uri,
  'active_group' => license_group
}

file 'server.conf' do
  path "#{node['splunk']['home']}/etc/system/local/server.conf"
  #content CernerSplunk::Conf::Writer.new(server_stanzas).write
  user node['splunk']['user']
  group node['splunk']['group']
  mode '0600'
  notifies :restart, 'service[splunk]', :delayed
end

