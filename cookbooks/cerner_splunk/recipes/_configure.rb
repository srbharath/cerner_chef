# frozen_string_literal: true

# Cookbook Name:: cerner_splunk
# Recipe:: _configure
#
# Configures the Splunk system post package installation

unless node.run_state['cerner_splunk']['configure_apps_only']
  # Verify that clusters are configured
  if node['splunk']['node_type'] != :license_server && node['splunk']['config']['clusters'].empty?
    if node['splunk']['node_type'] == :forwarder
      Chef::Log.warn 'No cluster data bag configured, ensure your outputs are configured elsewhere.'
    else
      Chef::Log.warn 'No cluster data bag configured, ensuring configuration for other components.'
      return  # Exit the recipe execution gracefully if no cluster data bags are configured
    end
  end

  node['splunk']['config']['clusters'].each do |cluster|
    begin
      cluster_data = CernerSplunk::DataBag.load(cluster, secret: node['splunk']['data_bag_secret'])
      unless cluster_data
        Chef::Log.warn "Unknown databag configured for node['splunk']['config']['clusters'] => '#{cluster}'"
        next
      end

      # Proceed with configuring based on cluster_data
    rescue Net::HTTPServerException => e
      Chef::Log.error "Failed to load data bag item: #{e.message}"
      next
    end
  end

  include_recipe 'cerner_splunk::_configure_server'
  include_recipe 'cerner_splunk::_configure_logs' unless node['splunk']['logs'].empty?
  include_recipe 'cerner_splunk::_configure_roles'
  include_recipe 'cerner_splunk::_configure_authentication'
  include_recipe 'cerner_splunk::_configure_inputs'
  include_recipe 'cerner_splunk::_configure_outputs'
  include_recipe 'cerner_splunk::_configure_alerts'
end

include_recipe 'cerner_splunk::_configure_apps'

