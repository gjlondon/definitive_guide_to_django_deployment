#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: application_python
# Provider:: django
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

include Chef::DSL::IncludeRecipe

action :before_compile do

  include_recipe "supervisor"

  raise "You must specify an application module to load" unless new_resource.config

  if !new_resource.restart_command
    new_resource.restart_command do
      run_context.resource_collection.find(:supervisor_service => "#{new_resource.application.name}-celeryd").run_action(:restart) if new_resource.celeryd
      run_context.resource_collection.find(:supervisor_service => "#{new_resource.application.name}-celerybeat").run_action(:restart) if new_resource.celerybeat
      run_context.resource_collection.find(:supervisor_service => "#{new_resource.application.name}-celerycam").run_action(:restart) if new_resource.celerycam
    end
  end

  new_resource.symlink_before_migrate.update({
    new_resource.config_base => new_resource.config,
  })

  new_resource.broker[:transport] ||= "amqplib"
  new_resource.broker[:host_role] ||= "#{new_resource.application.name}_task_broker"
  new_resource.broker[:host] ||= begin
    host = new_resource.find_matching_role(new_resource.broker[:host_role])
    raise "No task broker host found" unless host
    host.attribute?('cloud') ? host['cloud']['local_ipv4'] : host['ipaddress']
  end
end

action :before_deploy do

  new_resource = @new_resource

  template ::File.join(new_resource.application.path, "shared", new_resource.config_base) do
    source new_resource.template || "celeryconfig.py.erb"
    cookbook new_resource.template ? new_resource.cookbook_name.to_s : "application_python"
    owner new_resource.owner
    group new_resource.group
    mode "644"
    variables :broker => new_resource.broker, :results => new_resource.results
  end

  if new_resource.celerycam
    # turn on events automatically, if we are going to run celerycam
    new_resource.enable_events(true)
  end

  cmds = {}
  if new_resource.celeryd
    case new_resource.queues
    when Array
      cmds[:celeryd] = "celeryd -Q #{new_resource.queues.join(',')} #{new_resource.enable_events ? "-E" : ""}"
    when NilClass
      cmds[:celeryd] = "celeryd #{new_resource.enable_events ? "-E" : ""}"
    end
  end
  cmds[:celerybeat] = "celerybeat" if new_resource.celerybeat
  if new_resource.celerycam
    if new_resource.django
      cmd = "celerycam"
    else
      raise "No camera class specified" unless new_resource.camera_class
      cmd = "celeryev --camera=\"#{new_resource.camera_class}\""
    end
    cmds[:celerycam] = cmd
  end

  cmds.each do |type, cmd|
    supervisor_service "#{new_resource.application.name}-#{type}" do
      action :enable
      if new_resource.django
        django_resource = new_resource.application.sub_resources.select{|res| res.type == :django}.first
        raise "No Django deployment resource found" unless django_resource
        command "#{::File.join(django_resource.virtualenv, "bin", "python")} manage.py #{cmd}"
        environment new_resource.environment
      else
        command cmd
        if new_resource.environment
          environment new_resource.environment.merge({'CELERY_CONFIG_MODULE' => new_resource.config})
        else
          environment 'CELERY_CONFIG_MODULE' => new_resource.config
        end
      end
      directory ::File.join(new_resource.path, "current")
      autostart false
      user new_resource.owner
    end
  end

end

action :before_migrate do
end

action :before_symlink do
end

action :before_restart do
end

action :after_restart do
end
