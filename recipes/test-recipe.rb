#
# Cookbook:: my_cookbook
# Recipe:: test-recipe
#
# Copyright:: 2024, The Authors, All Rights Reserved.
package 'apache2' do
  action :install
end
service 'apache2' do
  action [:enable, :start]
end

