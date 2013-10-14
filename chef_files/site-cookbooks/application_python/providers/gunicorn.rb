#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: application_python
# Provider:: gunicorn
#
# Copyright:: 2011, Opscode, Inc <legal@opscode.com>
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

require 'tmpdir'

include Chef::DSL::IncludeRecipe

action :before_compile do

  include_recipe "supervisor"

  install_packages

  django_resource = new_resource.application.sub_resources.select{|res| res.type == :django}.first
  gunicorn_install "gunicorn-#{new_resource.application.name}" do
    virtualenv django_resource ? django_resource.virtualenv : new_resource.virtualenv
  end

  if !new_resource.restart_command
    new_resource.restart_command do
      run_context.resource_collection.find(:supervisor_service => new_resource.application.name).run_action(:restart)
    end
  end

  raise "You must specify an application module to load" unless new_resource.app_module

end

action :before_deploy do

  new_resource = @new_resource

  gunicorn_config "#{new_resource.application.path}/shared/gunicorn_config.py" do
    action :create
    template new_resource.settings_template || 'gunicorn.py.erb'
    cookbook new_resource.settings_template ? new_resource.cookbook_name.to_s : 'gunicorn'
    listen new_resource.bind ? "#{new_resource.bind}" : "#{new_resource.host}:#{new_resource.port}"
    backlog new_resource.backlog
    worker_processes new_resource.workers
    worker_class new_resource.worker_class.to_s
    #worker_connections
    worker_max_requests new_resource.max_requests
    worker_timeout new_resource.timeout
    worker_keepalive new_resource.keepalive
    #debug
    #trace
    preload_app new_resource.preload_app

    #daemon
    pid new_resource.pidfile
    #umask
    #logfile
    #loglevel
    #proc_name
  end

  supervisor_service new_resource.application.name do
    action :enable
    if new_resource.environment
      environment new_resource.environment
    end
    if new_resource.app_module == :django
      django_resource = new_resource.application.sub_resources.select{|res| res.type == :django}.first
      raise "No Django deployment resource found" unless django_resource
      base_command = "#{::File.join(new_resource.application.path, "shared", "env", "bin", "gunicorn")} #{new_resource.application.name}.wsgi:application"
    else
      gunicorn_command = new_resource.virtualenv.nil? ? "gunicorn" : "#{::File.join(new_resource.virtualenv, "bin", "gunicorn")}"
      base_command = "#{gunicorn_command} #{new_resource.app_module}"
    end
    command "#{base_command} -c #{new_resource.application.path}/shared/gunicorn_config.py"
    directory new_resource.directory.nil? ? ::File.join(new_resource.path, "current") : new_resource.directory
    autostart false
    environment "PATH"=> "#{new_resource.application.path}/shared/env/bin"
    user new_resource.owner
  end

end

action :before_migrate do
  install_requirements
end

action :before_symlink do
end

action :before_restart do
end

action :after_restart do
end

protected

def install_packages
  new_resource.packages.each do |name, ver|
    python_pip name do
      version ver if ver && ver.length > 0
      virtualenv new_resource.virtualenv
      action :install
    end
  end
end

def install_requirements
  if new_resource.requirements.nil?
    # look for requirements.txt files in common locations
    [
      ::File.join(new_resource.release_path, "requirements", "#{node.chef_environment}.txt"),
      ::File.join(new_resource.release_path, "requirements.txt")
    ].each do |path|
      if ::File.exists?(path)
        new_resource.requirements path
        break
      end
    end
  end
  if new_resource.requirements
    Chef::Log.info("Installing using requirements file: #{new_resource.requirements}")
    # TODO normalise with python/providers/pip.rb 's pip_cmd
    if new_resource.virtualenv.nil?
      pip_cmd = 'pip'
    else
      pip_cmd = ::File.join(new_resource.virtualenv, 'bin', 'pip')
    end
    execute "#{pip_cmd} install --src=#{Dir.tmpdir} -r #{new_resource.requirements}" do
      cwd new_resource.release_path
    end
  else
    Chef::Log.debug("No requirements file found")
  end
end
