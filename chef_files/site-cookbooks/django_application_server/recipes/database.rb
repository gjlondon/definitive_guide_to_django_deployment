#
# Author:: George London <@rogueleaderr>
# Cookbook Name:: definitive_guide_to_django_deployment
# Recipe:: database
#
# Copyright:: 2013, George London
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Install Postgres, a ruby shim to allow chef to operate on Postgres, and
# configure the Postgres server to use the full resources of the VM

include_recipe "sysctl"
include_recipe "postgresql::ruby"
include_recipe "postgresql::client"
include_recipe "postgresql::server"
include_recipe "postgresql::config_pgtune"
include_recipe "database"


# create our application database

postgresql_connection_info = {
    :host      => '127.0.0.1',
    :port      => 5432,
    :username  => 'postgres',
    :password  => node['postgresql']['password']['postgres']
}

database node["postgresql"]["db_name"] do
	connection postgresql_connection_info
	provider   Chef::Provider::Database::Postgresql
	action :create
end

# config_pgtune doesn't bump up the shmmax/shmall, meaning postgres can't be restarted
# without a sysctl call
# code from https://raw.github.com/styx/chef-postgresql/master/recipes/config_pgtune.rb

if node['postgresql'].attribute?('config_pgtune') &&
   node['postgresql']['config_pgtune'].attribute?('tune_sysctl') &&
   node['postgresql']['config_pgtune']['tune_sysctl']

  node.default['sysctl']['kernel']['shmmin'] = 1 * 1024 * 1024 * 1024 # 1 Gb
  node.default['sysctl']['kernel']['shmmax'] = node['memory']['total'].to_i * 1024
  node.default['sysctl']['kernel']['shmall'] = (node['memory']['total'].to_i * 1024 * 0.9 / 4096).floor

  bash "setup values immediately" do
    user 'root'
    group 'root'
    code <<-EOH
      sysctl -w kernel.shmmin=#{node.default['sysctl']['kernel']['shmmin']}
      sysctl -w kernel.shmmax=#{node.default['sysctl']['kernel']['shmmax']}
      sysctl -w kernel.shmall=#{node.default['sysctl']['kernel']['shmall']}
    EOH
  end

end

# restart the cluster to pick up changes
service 'postgresql' do
  supports :restart => true
  action :restart
end
