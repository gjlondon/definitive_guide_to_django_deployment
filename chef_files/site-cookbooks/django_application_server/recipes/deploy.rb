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

include_recipe "application"

# deploy the django application

application "#{node.app_name}" do
	only_if { node['roles'].include? 'deploy' }
	path "/srv/#{node.app_name}"
	owner "nobody"
	group "nogroup"
	repository "https://github.com/#{node.repo}.git"
	revision "master"
	symlink_before_migrate "local_settings.py"=>"#{node.app_name}/settings/local_settings.py"
	migrate true
	action :deploy

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

	end

end


