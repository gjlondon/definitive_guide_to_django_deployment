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

# Install basic packages our app will require

include_recipe "git"
include_recipe "nginx"
include_recipe "python"
include_recipe "rabbitmq"
include_recipe "postgresql::client"
include_recipe "application"
include_recipe "memcached"

# Read in and set basic configuration variables

node.default["env_name"] = "#{node.app_name}-env"
node.default["env_home"] = "#{node.project_root}/#{node.env_name}"
node.default["app_home"] = "#{node.project_root}/#{node.app_name}"
settings = Chef::EncryptedDataBagItem.load("config", "config_1")
settings_string = "import os\n"
settings.to_hash.each do |key, value|
	settings_string << "os.environ['#{key}'] = '#{value}'\n"
end

# Update ubuntu and install necesary packages

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

=begin
node.pip_python_packages.each do |pkg|
    execute "install-#{pkg}" do
        command "pip install #{pkg}"
        not_if "[ `pip freeze | grep #{pkg} ]"
    end
end
=end

# Insert an nginx template for our site into nginx sites-available,
# symlink to sites-enabled, disable the default site,  and restart nginx

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
	symlinks("local_settings.py"=>"#{node.app_name}/settings/local_settings.py")
	migrate true

	django do
		requirements "requirements/requirements.txt"
		settings_template "settings.py.erb"
		debug false
		local_settings_file "local_settings.py"
		collectstatic "collectstatic --noinput"
		database_host   node["postgresql"]["database_ip"]
		database_name   node["postgresql"]["database_name"]
		database_engine  "postgresql_psycopg2"
		database_username  "postgres"
		allowed_hosts "[\"#{node.site_domain}\", \"#{node.ec2_dns}\"]"
		database_password  node["postgresql"]["password"]["postgres"]
	end

	gunicorn do
		only_if { node['roles'].include? 'application_server' }
		app_module :django
		#logfile "gunicorn.log"
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
end

# create a file with our "secret" settings for our Django app

file "/srv/#{node.app_name}/shared/cached-copy/project.settings" do
    content settings_string
    mode "440"
    owner "ubuntu"
    group "ubuntu"
    action :create
end
