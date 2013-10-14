#
# Author:: Noah Kantrowitz <noah@opscode.com>
# Cookbook Name:: application_python
# Resource:: celery
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

include ApplicationCookbook::ResourceBase

attribute :config, :kind_of => [String, NilClass], :default => nil
attribute :template, :kind_of => [String, NilClass], :default => nil
attribute :django, :kind_of => [TrueClass, FalseClass], :default => false
attribute :celeryd, :kind_of => [TrueClass, FalseClass], :default => true
attribute :celerybeat, :kind_of => [TrueClass, FalseClass], :default => false
attribute :celerycam, :kind_of => [TrueClass, FalseClass], :default => false
attribute :camera_class, :kind_of => [String, NilClass], :default => nil
attribute :enable_events, :kind_of => [TrueClass, FalseClass], :default => false
attribute :environment, :kind_of => [Hash], :default => {}
attribute :queues, :kind_of => [Array,NilClass], :default => nil

def config_base
  config.split(/[\\\/]/).last
end

def broker(*args, &block)
  @broker ||= Mash.new
  @broker.update(options_block(*args, &block))
  @broker
end

def results(*args, &block)
  @results ||= Mash.new
  @results.update(options_block(*args, &block))
  @results
end
