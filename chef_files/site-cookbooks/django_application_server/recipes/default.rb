#
# Cookbook Name:: django_application_server
# Recipe:: default
#
# Copyright 2013, George London
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

require 'rubygems'
require 'json'

include_recipe "git"
include_recipe "apt"
include_recipe "nginx"
include_recipe "python"
include_recipe "rabbitmq"
include_recipe "build-essential"
include_recipe "postgresql::client"
include_recipe "application"
include_recipe "memcached"

node.default["env_name"] = "#{node.app_name}-env"
node.default["env_home"] = "#{node.project_root}/#{node.env_name}"
node.default["app_home"] = "#{node.project_root}/#{node.app_name}"

# a ridiculously roundabout way of getting the node variable into the block
=begin
db_line = <<HERE
			database  "#{node.app_name}"
			engine  "postgresql_psycopg2"
			username  "#{node.app_name}"
			password  "#{node.database_password}"
HERE
puts "DB LINE #{db_line}"
proc_line = "Proc.new { '#{db_line}' }"
puts "PROcc #{proc_line}"
node.default[:database] = eval "Proc.new { puts 7777777 }"
puts "DEFF #{node[:database]}"
=end

execute "Update apt repos" do
   command "apt-get update"
end

node.ubuntu_packages.each do |pkg|
    package pkg do
        :upgrade
    end
end

# setup a nice bash shell configuration
template "/home/ubuntu/.bashrc" do
  source "bashrc.erb"
  mode 0644
  owner "ubuntu"
  group "ubuntu"
  variables(
    :role => node.name,
    :prompt_4color => node.prompt_color)
end

node.pip_python_packages.each do |pkg|
    execute "install-#{pkg}" do
        command "pip install #{pkg}"
        not_if "[ `pip freeze | grep #{pkg} ]"
    end
end


settings = Chef::EncryptedDataBagItem.load("config", "config_1")
settings_string = "import os\n"
settings.to_hash.each do |key, value|
	settings_string << "os.environ['#{key}'] = '#{value}'\n"
end


# Set up nginx sites-enabled and restart on changes

puts "PTTG #{node.site_domain}"
template "/etc/nginx/sites-available/#{node.app_name}.conf" do
  source "nginx-conf.erb"
  owner "root"
  group "root"
  variables(
    :domain => node.site_domain,
    :app_home => "/srv/#{node.app_name}/current",
    :env_home => "/srv/#{node.app_name}/shared/env",
    :app_name => "#{node.app_name}"
    )
  notifies :restart, "service[nginx]"
end

nginx_site "default" do
    enable false
end

nginx_site "#{node.app_name}.conf"

service 'nginx' do
  supports :restart => true, :reload => true
  action :enable
end

# deploy the django application and configure celery and gunicorn

application "#{node.app_name}" do
	only_if { node['roles'].include? 'application_server' }
	path "/srv/#{node.app_name}"
	owner "nobody"
	group "nogroup"
	repository "https://github.com/#{node.repo}.git"
	revision "master"
	symlink_before_migrate "local_settings.py"=>"#{node.app_name}/settings/local_settings.py"
	migrate true

	before_symlink do
		raise "foo"
	end

	django do
		requirements "requirements/requirements.txt"
		settings_template "settings.py.erb"
		debug true
		local_settings_file "local_settings.py"
		collectstatic "collectstatic --noinput"
		database_host   node["postgresql"]["database_ip"]
		database_name   node["postgresql"]["database_name"]
		database_engine  "postgresql_psycopg2"
		database_username  "postgres"
		database_password  node["postgresql"]["password"]["postgres"]
=begin
		database do
			database "packaginator"
			engine "postgresql_psycopg2"
			username "packaginator"
			password "awesome_password"
		end
=end
		#database_master_role "database_master"
	end

	gunicorn do
		only_if { node['roles'].include? 'application_server' }
		app_module :django
		bind "unix:/tmp/gunicorn_#{node.site_domain}.sock"
	end

	celery do
		only_if { node['roles'].include? 'application_server' }
		config "celery_settings.py"
		django true
		celerybeat true
		celerycam true
		broker do
			transport "rabbitmq"
			host "localhost"
		end
	end

	nginx_load_balancer do
		only_if { node['roles'].include? '#{app_name}_load_balancer' }
		application_port 8080
		static_files "/static" => "static"
	end

end

file "/srv/#{node.app_name}/shared/cached-copy/project.settings" do
    content settings_string
    mode "440"
    owner "ubuntu"
    group "ubuntu"
    action :create
end
