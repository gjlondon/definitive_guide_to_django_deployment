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

# restart the cluster to pick up changes
service 'postgresql' do
  supports :restart => true
  action :restart
end
