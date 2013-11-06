#Idiomatic Django Deployment - The Definitely Definitive Guide

Wow, this guide is long. Why not skip it? [I'm available to freelance](mailto:george.j.london@gmail.com?subject=Help me deploy Django&body=Gee, I'm already writing this email. I guess I might as well hire you.).

Or, if you're kind of excited by how long this guide is, consider [following me on Twitter](http://www.twitter.com/rogueleaderr) or [subscribing to my newsletter](http://eepurl.com/GeOqP).

# Overview

**By the end of this guide, you should be have a simple but stable actually deployed
  Django website accessible at a public URL**. So anyone in the world will be
  able to visit "www.yourapp.com" and see a page that says "Hello World!"

You'll go through the following steps:

1. [Setting up a host server for your webserver and your database](#servers).
2. [Installing and configuring the services your site will need](#services).
3. [Automating deployment of your code](#code).
4. [Learning what to do when things go wrong](#debug)
5. Next time: [Going beyond the basics with caching, monitoring etc.](#monitoring)

###Why This Guide Is Needed

Over the last two years, I've taught myself to program in order to
build my startup [LinerNotes.com](http://www.linernotes.com). I
started out expecting that the hardest part would be getting my head
around the sophisticated algorithmic logic of programming. To my
surprise, I've actually had to do very little difficult algorithmic work.[[1]](#note_algo) Instead, the hardest part has been getting proficient at using the
*many* different tools in the programmer's utility belt. From emacs to
gunicorn, building a real project requires dozens of different
tools. Theoretically, one can *a priori* reason through a red-black
tree but there's just no way to learn emacs without the reading the
manual. LinerNotes is actually a lot more complicated under the hood
than it looks on the surface and so I've had to read quite a lot of
manuals.

The point of this guide is to save you some of that trouble. Sometimes
trouble is good -- struggling to design and implement an API builds
programming acumen. But struggling to configure nginx is just a waste
of time. I've found many partial guides to Django deployment but
haven't found any single, recently updated resource that lays out the
**simple, Pythonic way of deploying a Django site in
production**. This post will walk you through creating such a set
up. But it *won't* introduce you to basic DevOps 101 concepts. See the bottom for a glossary of acronyms and explanatory footnotes (because Github breaks my intra-page links).[[2]](#note_devops)

**Disclaimer**: I'm **definitely** not the most qualified person to write this post. I'm just the only one dumb enough to try. If you object to anything in this post or get confused or find something broken, **help make it better**. 
Leave a helpful comment (or even better submit a pull request to the Github repo.) The full text of this post is available in the repo and I'll update this guide as approriate.

###Overview of the Final Architecture

Our example site is just a "hello world" app, but this is going to be the most well-implemented, stable, and scalable
"hello world" application on the whole world wide web. Here's a diagram of how
your final architecture will look:

![Architecture Diagram](https://raw.github.com/rogueleaderr/definitive_guide_to_django_deployment/master/django_deployment_diagram.png)

Basically, users send HTTP requests to your server, which are intercepted and
routed by the nginx load balancer. Requests for dynamic content will be routed to
your [WSGI](http://wsgi.readthedocs.org/en/latest/what.html)[[3]](#cred_3) server (Gunicorn) and requests for static content will be served
directly off the server's file system. Gunicorn has a few helpers, memcached and celery,
which respectively offer a cache for repetitive tasks and an asynchronous queue
for long-running tasks.

We've also got our Postgres database (for all your lovely models) which we run on a
separate EC2 server.[[4]](#note_server_balance)

See [below](#understand_services) for a more detailed description of what each component
actually does.


<a id="servers"></a>
#Set Up Your Host Servers

###Set up AWS/EC2

Since this guide is trying to get you to an actual publicly accessible site,
we're going to go ahead and build our site on the smallest, freest Amazon [EC2](#gloss_ec2) instance available, the trusty "micro". If you don't want to use
EC2, you can set up a local virtual machine on your laptop using 
[Vagrant](http://www.vagrantup.com/) or use your own existing server (you'll have to tweak my scripts a little). I'm also intrigued by the
[Docker project](https://www.docker.io/) -- it claims to allow deployment of
whole application components in platform agnostic "containers." But Docker
itself says it's not stable enough for production; who am I to
disagree?[[5]](#note_docker)

Anyway, we're going to use EC2 to set up the smallest possible host for our webserver and another
one for our database.

For this tutorial, you'll need an existing EC2 account. There are [many tutorials on setting up an account](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/get-set-up-for-amazon-ec2.html) so I'm not going to walk you through the account setup.

Python has a very nice library called [boto](https://github.com/boto/boto) for administering AWS
from within code. And another nice tool called [Fabric](http://docs.fabfile.org/en/1.7/) for creating
command-line directives that execute Python code that can *itself* execute
shell commands on local or remote servers. We're going to use Fabric
to definite all of our administrative operations, from
creating/bootstrapping servers up to pushing code. I've read that Chef (which we'll use below) also has a [plugin to launch EC2 servers](http://docs.opscode.com/plugin_knife_ec2.html) but I'm going to prefer boto/Fabric because they give us the option of embedding all our "command" logic into Python and editing it directly as needed.

Start off by cloning the Github repo for this project onto your local machine.

    git clone git@github.com:rogueleaderr/definitive_guide_to_django_deployment.git
    cd definitive_guide_to_django_deployment

I'm assuming that if you want to deploy Django, you already have
Python and pip and [virtualenv](http://www.virtualenv.org/en/latest/)
on your laptop. But just to check:

    python --version
    pip --version
    virtualenv --version

This process requires a number of Python dependencies which we'll
install into a virtualenv (but won't track with git):[[6]](#note_2)

    virtualenv django_deployment_env
    source django_deployment_env/bin/activate
    # install all our neccesary dependencies from a requirements file
    pip install -r requirements.txt

    # or, for educational purposes, individually
    pip install boto
    pip install fabric
    pip install awscli

The github repo includes a fabfile.py[[7]](#cred_1) which provides all the
commandline directives we'll need. But fabfiles are pretty intuitive
to read, so try to follow along with what each command is doing.

First, we need to set up [AWS](#gloss_aws) credentials for boto to use. In keeping
with the principles of the [Twelve Factor App](http://12factor.net/)
we store configuration either in environment variables or in config
files which are not tracked by VCS. You can you AWS access and secret keys on your [AWS security page](https://portal.aws.amazon.com/gp/aws/securityCredentials).

    echo '
    aws_access_key_id: <YOUR KEY HERE>
    aws_secret_access_key: <YOUR SECRET KEY HERE>
    region: "<YOUR REGION HERE, e.g. us-east-1>"
    key_name: <YOUR EC2 KEY NAME>
    key_dir: "~/.ec2"
    group_name: <YOUR SECURITY GROUP NAME>
    ssh_port: 22
    instance_type: "t1.micro
    ubuntu_lts_ami: "ami-d0f89fb9"' > aws.cfg
    echo "aws.cfg" >> .gitignore


We're using an [AMI](#gloss_ami) for a "free-tier" eligible Ubuntu image.

While we're at it, let's create a config file that will let you use
the AWS [CLI](#gloss_cli) directly:

    mkdir ~/.aws
    echo '
    aws_access_key_id = <YOUR KEY HERE>
    aws_secret_access_key = <YOUR SECRET KEY HERE>
    region = <YOUR REGION HERE, e.g. us-east-1>' > ~/.aws/config

**We're also going to create a settings file that contains all the configuration for our actual app.** 

    touch settings.json
    echo "settings.json" >> .gitignore

**Do not track the settings.json file in git.**

Now we're going to use a Fabric directive to setup our AWS account [[6]](#cred_2) by:

1. Configuring a keypair ssh key that will let us log in to our servers
2. Setting up a security group that defines access rules to our servers

To use our first fabric directive and setup our AWS account, go to the directory where our fabfile lives and
do

    fab setup_aws_account

###Launch Some EC2 Servers

We're going to launch two Ubuntu 12.04 LTS servers, one for our web host
and one for our database. We're using Ubuntu because it it seems to be
the most popular linux distro right now, and 12.04 because it's a (L)ong (T)erm (S)upport
version, meaning we have the longest period before it's official
deprecated and we're forced to deal with an OS upgrade.

With boto and Fabric, launching a new instance is very easy:

    fab create_instance:webserver
    fab create_instance:database

These commands tell Fabric to use boto to create a new "micro"
(i.e. free for the first year) instance on EC2, with the name you
provide. You can also provide a lot more configuration options to this
directive at the command line but the defaults are sensible for now.

You'll also be given the option to add the instance information to
your ~/.ssh/config file so that you can login to your instance
directly with

    ssh webserver

If you create an instance by mistake, you can terminate it with

    fab terminate_instance webserver

(You'll have to manually delete the ssh/config entry)

<a id="services"></a>
#Install and Configure Your Services

We need a project to deploy. Your easiest option is to just clone the sample project I've created:

    git clone git@github.com:rogueleaderr/django_deployment_example_project.git

If you don't do that, then you need to...

###Make sure your project is set up correctly:

This guide assumes a standard Django 1.5 project layout with a few small tweaks:

* Your settings should be comprised of three files:

        app
        \--settings
            \--__init__.py # tells python how to import your settings
             --base.py # your default settings
             --local_settings.py # settings that will be dynamically generated from your settings.json. don't track in git

    And your \_\_init\_\_.py should consist of:

        # application_python cookbook expects manage.py in a top level
        # instead of app level dir, so the relative import can fail
        try:
            from .<PROJECT_NAME>.<PROJECT_NAME>.settings.base import *
        except ImportError:
            from <PROJECT_NAME>.settings.base import *

        try:
            from local_settings import *
        except ImportError:
            pass

    Our bootstrapping process will create a local_settings.py but to develop locally you'll need to make one manually with your database info etc. (Don't check it into git.)

* We're serving static files with [dj-static](https://github.com/kennethreitz/dj-static). To use dj-static, you need a couple project tweaks:

    In base.py, set

        STATIC_ROOT = 'staticfiles'
        STATIC_URL = '/static/'

    Modify your wsgi.py:

        from django.core.wsgi import get_wsgi_application
        from dj_static import Cling

        application = Cling(get_wsgi_application())    

* Your installed apps must contain your project app and also `djcelery`.

<a id="understand_services"></a>
###Understand the services
Our stack is made up of a number of services that run
semi-independently:

**Gunicorn**: Our WSGI webserver. Gunicorn receives HTTP requests fowarded to it from nginx, executes
  our Django code to produce a response, and returns the response which nginx transmits back to the client.
  
**Nginx**: Our
  load balancer (a.k.a. "[reverse proxy server](http://en.wikipedia.org/wiki/Reverse_proxy)"). Nginx takes requests from the open internet and decides
  whether they should be passed to Gunicorn, served a static file,
  served a "Gunicorn is down" error page, or even blocked (e.g. to prevent denial-of-service
  requests.) If you want to spread your requests across several Gunicorn nodes, it just takes a tiny change to your nginx configuration.

**Memcached**: A simple in-memory key/value caching system. Can save
  Gunicorn a lot of effort regenerating rarely-changed pages or objects.

**Celery**:   An async task system for Python. Can take longer-running
  bits of code and process them outside of Gunicorn without jamming up
  the webserver. Can also be used for "poor man's" concurrency in Django.

**RabbitMQ**: A queue/message broker that passes asynchronous tasks
  between Gunicorn and Celery.

**Supervisor**: A process manager that attempts to make sure that all key services stay
  alive and are automatically restarted if they die for any reason.

**Postgres**: The main database server ("cluster" in Postgres
  parlance). Contains one or more "logical" databases containing our
  application data / model data.
  
###Install the services

We could install and configure each service individually, but instead
we're going to use a "configuration automation" tool called
[Chef](http://www.opscode.com/chef/). Chef lets us write simple Ruby
programs (sorry Python monogamists!) called Cookbooks that automatically
install and configure services.

Chef can be a bit intimidating. It provides an entire Ruby-based
[DSL](#gloss_dsl) for expressing configuration. And it
also provides a whole system (Chef server) for controlling the
configuration of remote servers (a.k.a. "nodes") from a central location. The DSL is
unavoidable but we can make things a bit simpler by using "Chef Solo", a stripped down version of Chef that does away with the whole central server and leaves us with
just a single script that we run on our remote servers to bootstrap our
configuration.

(Hat tip to several authors for blog posts about using Chef for Django[[8]](#cred_4))

####Wait, a complicated ruby tool? Really?

Yes, really. Despite being in Ruby[[9]](#note_salt), Chef has some great advantages that make it worth learning (at least enough to follow this guide.)

1. *It lets us fully automate our deployment*. We only need to edit *one* configuration file and run two commands and our *entire stack* configures itself automatically. And if your servers all die you can redeploy from scratch with the same two commands (assuming you backed up your database).
2. *It lets us lock the versions for all of our dependencies*. Every package installed by this process has its version explicitly specified. So this guide/process may become dated but it should continue to at least basically work for a long time.
3. *It lets us stand on the shoulders of giants*. Opscode (the creators of Chef) and some great OSS people have put a lot of time into creating ready-to-use Chef "cookbooks" for nearly all our needs. Remember, *DRW-EWTMOTWWRS* (Don't Re-Invent the Wheel, Especially When the Maker of the Wheel Was Really Smart).

Okay, buckle up. We're going to need to talk a little about how Chef works. But it'll be worth it.

At the root, Chef is made up of small Ruby scripts called *recipes* that express
configuration. Chef *declares* configuration rather than executing a
series of steps (the way Fabric does). A recipe is supposed to describe all the resources that
are available on a server (rather than just invoking installation
commands.) If a resource is missing when a recipe is run, Chef will
try to figure out how to install that resource. If a configuration file has the wrong information, Chef will fix(/brutally overwrite) it. Recipes are
(supposed to be) *idempotent*, meaning that if you run a recipe and
then run it again then the second run will have no effects.

But which recipes to run? Chef uses *cookbooks* that
group together recipes for deploying a specific tool (e.g. "the git
cookbook"). And Chef has a concept called "roles" that let you specify
which cookbooks should be used on a given server. So for example, we
can define a "webserver" role and tell Chef to use the "git", "nginx"
and "django" cookbooks. Opscode (the makers of Chef) provide a bunch
of pre-packaged and (usually well maintained) cookbooks for common
tools like git. And although Chef cookbooks can get quite complicated, they are just code and so they can be version controlled with git.


####Set up Chef

First, install Ruby:

    #brew install rbenv (the virtualenv equivalent)
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.zshrc # or .bashrc
    echo 'eval "$(rbenv init -)"' >> ~/.zshrc # or .bashrc
    rbenv install 1.9.3-p448
    rbenv global 1.9.3-p448
    #install bundler, the pip equivalent
    gem install bundler

Install some tools that simplify working with Chef ([Knife Solo](https://github.com/matschaffer/knife-solo), [Knife Solo Data Bag](https://github.com/thbishop/knife-solo_data_bag), [Berkshelf](http://berkshelf.com/), and [Knife-solo\_data\_bag](https://github.com/thbishop/knife-solo_data_bag)):

    # Install all the gems in the file "Gemfile"
    bundler install
    # Ruby requires rehashing to use new command line options
    rbenv rehash


###Chef, [make me a server-which](http://xkcd.com/149/).

We're going to have two nodes, a webserver and a database. We'll have four roles:

1. base.rb (common configuration that both will need, like apt and git)
2. application_server.rb (webserver configuration)
3. database.rb (database configuration)
4. deploy.rb (to save time, a stripped down role that just deploys app code to the app server)

The role definitions live in `chef_files/roles`. Now we just need to tell Chef which roles apply to which nodes, and we do that in our chef\_files/nodes folder in files named "{node name}\_node.json". If you use names other than "webserver" and "database" for your nodes, **you must rename these node files.**

Any production Django installation is going to have some sensitive
values (e.g. database passwords). Chef has a construct called *data
bags* for isolating and storing sensitive information. And these bags
can even be encrypted so they can be stored in a [VCS](#gloss_vcs). Knife solo lets us create a databag and encrypt
it. Fabric will automatically upload our databags to the server where
they'll be accessible to our Chef solo recipe.

Start by loading the values we need into our settings.json file. 

    echo '{
    "id": "config_1",
    "POSTGRES_PASS": "<YOUR DB PASSWORD>",
    "DEBUG": "False",
    "DOMAIN": "<YOUR DOMAIN NAME>",
    "APP_NAME": "<YOUR APP NAME>",
    "DATABASE_NAME": "<YOUR DATABASE NAME>",
    "REPO": "<YOUR GITHUB REPO NAME>",
    "GITHUB_USER": "<YOUR GITHUB USERNAME>",
    "DATABASE_IP": "DB_IP_SLUG",
    "EC2_DNS": "WEB_IP_SLUG"
    }' \
    | sed -e s/DB_IP_SLUG/`cat fab_hosts/database.txt`/ \
    | sed -e s/WEB_IP_SLUG/`cat fab_hosts/webserver.txt`/ \
    > settings.json
    
Now we need an encryption key (which we will *NOT* store in Github):

    cd chef_files
    openssl rand -base64 512 > data_bag_key
    cd ..
    # if you aren't using my repo's .gitingore, add the key
    echo "chef_files/data_bag_key" >> .gitignore


Now we can use the knife-solo to create an encrypted data bag from our settings.json file:

    cd chef_files
    knife solo data bag create config config_1 --json-file ../settings.json
    cd ..

Our `chef_files` repo contains a file `Berksfile` that lists all the cookbooks we are going to install on our server, along with specific versions. Knife solo will install all of these with a tool called [Berkshelf](http://berkshelf.com/), which I honestly assume is named after [this](http://i.qkme.me/3pjyup.jpg). If a cookbook becomes dated, just upgrade the version number in `chef_files/Berksfile`.
Now we're going to use Fabric to tell Chef to first bootstrap our database and then bootstrap our webserver. Do:

    fab bootstrap:database
    fab bootstrap:webserver

This will:

1. Install Chef
2. Tell Chef to configure the server

A lot of stuff is going to happen so this may take a while. Don't worry if the process seems to pause for a while. But if it exits with an error *please* [create an issue](https://github.com/rogueleaderr/definitive_guide_to_django_deployment/issues) on Github describing what went wrong (or better yet, leave a pull a request to fix it.)

####What is this magic?

Chef actually does *so much* that you might be reluctant to trust it. You may(/should) want to understand the details of your deployment. Or you may just distrust Ruby-scented magic. So here's a rough walk-through of everything the bootstrap scripts do.

#####Database

The database role first installs the essential base packages specified in [base.rb](https://github.com/rogueleaderr/definitive_guide_to_django_deployment/blob/master/chef_files/roles/base.rb), i.e. apt, gcc, etc, and sets up our ubuntu admin user with passwordless sudo.

Then we run our custom [database recipe](https://github.com/rogueleaderr/definitive_guide_to_django_deployment/blob/master/chef_files/site-cookbooks/django_application_server/recipes/database.rb) that:

1. Installs Postgres on the server

2. Modifies the default postgresql.conf settings to take full advantage of the node's resources (dynamically calculated using a cookbook called [ohai](http://docs.opscode.com/ohai.html).) Changes the Linux shmmax/shmall paramaters as necessary.

3. Tells Postgres to listen on all ports and accept password authenticated connections from all IP's (which is okay because we use Amazon's firewall to block any connection to the Postgres node from outside our security group.)

4. Creates our application database using a password and database name read in from our settings.json file.

5. Restarts Postgres to pick up the configuration changes.

#####Webserver

Again, install base packages per base.rb.

Then runs our main [application server setup recipe](https://github.com/rogueleaderr/definitive_guide_to_django_deployment/blob/master/chef_files/site-cookbooks/django_application_server/recipes/default.rb):

1. Runs Opscode cookbooks to install basic packages, including: git, nginx, python-dev, rabbit-mq, memcached, and postgres-client.

2. Reads configuration variables from our encrypted data bag (made from settings.json)

3. Updates Ubuntu and installs the bash-completion package. Creates a .bashrc from a template.

4. Creates an nginx configuration for our site from a template, load it into nginx's configuration folder  and restart nginx.

5. Deploy our Django app, which consists of:

   * Create a folder called `/srv/<APP_NAME>` that will hold our whole deployment
   
   * Create a folder called `/srv/<APP_NAME>/shared` with will hold our virtualenv and some key configuration files
   
   * Download our latest copy of our Github repo to `/srv/<APP_NAME>/shared/cached-copy`
   
   * Create a `local_settings.py` file from a template and include information to connect to the database we created above (details loaded from our data bag.)
   
   * "Migrate" (i.e. sync) the database with `manage.py syncdb`. The sync command can be overwritten if you want to use [South](http://south.aeracode.org/).
   
   * Install all our Python packages with pip from `requirements/requirements.txt`.
   
   * Run `manage.py collectstatic` to copy our static files (css, js, images) into a single static folder
   
   * Install gunicorn and create a configuration file from a template. The config file lives at `/srv/<APP_NAME>/shared/gunicorn_config.py`.
   
   * Bind gunicorn to talk over a unix socket named after our app
   
   * Install celery, along with celery's built-in helpers celerycam and celerybeat. Create a configuration file from a template. The config lives at `/srv/<APP_NAME>/shared/celery_settings.py`.
   
   * Create "supervisor" stubs that tell supervisor to manage our gunicorn and celery processes.

   * Copy the 'cached-copy' into a `/srv/<APP_NAME>/releases/<SHA1_HASH_of_release>` folder'. Then symlink the latest release into `/srv/<APP_NAME>/current` which is where where the live app ultimately lives.
   

6. Create a "project.settings" file that contains the sensitive variables (e.g. database password) for our Django app.

**Hopefully this list makes it a bit more clear why we're using Chef**. You certainly *could* do each of these steps by hand but it would be much more time consuming and error-prone.
    



###Make it public.

If Chef runs all the way through without error (as it should) you'll now have a 'Hello World' site accessible by opening your browser and visiting the "public DNS" of your site (which you can find from the EC2 management console or by doing `cat fab_hosts/webserver.txt`). But you probably don't want visitors to have to type in "103.32.blah-blah.ec2.blah-blah". You want them to just visit "myapp.com" and to do that you'll need to visit your domain registrar (e.g. GoDaddy or Netfirms) and **change your A-Record** to point to the IP of your webserver (which can also be gotten from the EC2 console or by doing):

    ec2-describe-instances | fgrep `cat fab_hosts/webserver.txt` | cut -f17

Domain registrars vary greatly on how to change the A-record so check your registrar's instructions.


<a id="code"></a>
#Automatically Deploy Your Code

Well, this is simple. Just commit your repo and do

    git push origin master

Then back in the deployment guide folder, do:

    fab deploy:webserver

<a id="debug"></a>
#Debugging:

###Nginx

Nginx is the proxy server that routes HTTP traffic. It has never once gone
down for me. It should start automatically if the EC2 server restarts.

If you need to start/restart nginx, log in to the webserver and do:

    sudo service nginx restart

If nginx misbehaves, logs are at:

    /var/log/nginx/

If, for some reason, you need to look at the nginx conf it's at:

    sudo emacs /etc/nginx/sites-available/<APP_NAME>.conf

If you need to edit it, avoid making changes to any conf files on the server, instead change:

    chef_files/site-cookbooks/django_application_server/templates/default/nginx-conf.erb

And rerun the Chef bootstrap process. It's idempotent so it won't change anything else (unless you've been tinkering directly with the server in which case your changes will be "reeducated").


###RabbitMQ

Another service that's started automatically. I have literally never had to interact
directly with it. But if can also be restarted by

    sudo service restart rabbitmq


###Memcached

Memcached is also a service and starts automatically if the EC2 node restarts. Unless you've designed a monstrosity, your site
should also continue to function if it dies (just be slow). Caching issues can sometimes
cause weird page content, so if something seems unusually bizarre try flushing the cache
by restarting memcached:

    sudo service restart memcached

Memcached is pretty fire and forget...since it's in memory it's theoretically possible it
could fill up and exhaust the memory on the webserver (I don't have a size cap and I make my TTL's
very long) but that has never happened so far. If it does, just reset memcached and it
will clear itself out.

#### To start Gunicorn/Celery:

Gunicorn and the Celery Workers are controlled by *Supervisor*, which is a Linux process runner/controller. Supervisor will automatically restart them if
they're terminated abnormally.

The Supervisor configuration is located at:

    /etc/supervisor/conf.d/<APP_NAME>.conf

To restart gunicorn and celery together, simply do:

    fab restart

To restart manually, you can use a Supervisor utility called *supervisorctl* that lets you check the status of and
restart processes. So if you need to restart gunicorn or celery, you can do:

    sudo supervisorctl restart <APP_NAME>
    sudo supervisorctl restart <APP_NAME>-celeryd

Or to check process status, just do

    sudo supervisorctl status

Supervisor routes all log output from managed processes to `/var/log/supervisor/<process-name-and-long-character-string>`. So if your server is behaving badly you can start there.

I keep a [GNU screen](http://www.gnu.org/software/screen/) active in the log directory so
I can get there quickly if I need to. You can get there with

    screen -r <MY SCREEN>

###Postgres

Postgres is a very stable program but can be a bit touchy on a small server under heavy load. It's probably
the most likely component to give you trouble (and sadly basically your whole site becomes totally
non-operational if it goes down.)

Postgres runs as a service so if you need to restart it (try not to need to do this) you
can do:

    sudo service postgresql restart

The disk can also fill (especially if something gets weird with the logging.) To check disk space:

    df -h

If a disk is 99% full, find big files using

    find / -type f -size +10M -exec ls -l {} \;

EC2 instances (larger than our micro type) all have "instance store" disks on /mnt, so you can copy obviously
suspicious files onto the instance store and let me sort it out later.

If that's not enough, check the logs for the service at `/var/log/postgresql/`


<a id="monitoring"></a>
#[Future Crimes](http://www.linernotes.com/o/1/dfc3217c-4580-480f-983f-3f23f73954da) of Configuration

This guide has gotten long enough for now, so I'm going to see how it's recieved before delving into advanced topics. But here are a few quick suggestions:

###Set Up Monitoring

There are a bunch of open and closed source solutions. They're all a bit more complicated than I'd like to set up. But here's what I personally use:

####Datadog Monitoring

[Datadog](http://www.datadoghq.com/) makes pretty metric dashboards. It will automatically monitor server CPU/memory/etc status. Datadog can send an
alert if there's no CPU activity from the webserver or the database (probably meaning the
EC2 servers are down.) And it can also hook into a custom statsd library and lets you emit/graph whatever metrics you want from anywhere in your app. You just have to decorate your code by hand. 


####Notifications / PagerDuty

[PagerDuty](http://www.pagerduty.com/) is a website that will call or email you if something goes wrong with a
 server. I've configured it to email/SMS if anything goes wrong with my site. 

Django by default automatically emits error emails, which I:

1. route to PagerDuty so it automatically sets up an "incident" and SMS's me
2. sends an email to me with the details of the error

Occasionally these emails are for non-serious issues but there's no easy way to
filter. It can be a bit chatty if you haven't chased down all the random non-critical errors in your app, but it helps save you from being unaware your site was down for 12 hours.

###Connection pooling

As of Django 1.5, Django opens a new Postgres connection for every request, which requires a ~200ms SSL renegotiation. Skip that overhead by using a connection pooler like [django-postgrespool](https://github.com/kennethreitz/django-postgrespool). You can also use [PgBouncer](http://wiki.postgresql.org/wiki/PgBouncer) on your Postgres server to make sure you don't get overwhelmed with incoming connections.

Apparently Django 1.6 includes a built-in connection pooler.

###Cache Settings

A *lot* of what Django does from request to request is redundant. You can hugely increase responsiveness and decrease server load by caching aggressively. Django has built in settings to cache views (but you have to enable caching yourself.) You can also use [cache-machine](https://cache-machine.readthedocs.org/en/latest/) to cache your models and significantly reduce your database load.

###Backup

The nice thing about this Chef setup is that if anything goes wrong with your webserver, it might actually be faster to deploy a new one from scratch and fail over than to try to restore your broken server. But you've still **got to back up your database**. Nothing can help you with deleted data. Postgres has a number of options, including *streaming replication* and [*(w)rite(a)head (l)og WAL shipping to S3*](http://blog.opbeat.com/2013/01/07/postgresql-backup-to-s3-part-one/).

###South migrations

Just use them. Also apparently baked into Django 1.6.

###Gevent

In my experience, by far the biggest cause of slowness in Django is I/O or network requests (e.g. calling an external API to supply some data for a widget.) By default, Python blocks the thread making the call until it's done. Gunicorn gives you "workers" which run in separate threads, but if you have four workers and they all block waiting for a long database query then your whole site will just hang until a worker is free (or the request times out.)

You can make things *way* faster by using "green threading" via [gevent](http://www.gevent.org/). Green threading is conceptually complicated (and occasionally buggy) but the basic idea is that one thread can contain many "green" threads. One one green thread runs at a time, but if it needs to wait for I/O it cedes control to another green thread. So your server can accomodate *way* more requests by never blocking the gunicorn worker threads.

#Wrap up

**And there you go. You've got a production-ready Django website.** It's reasonable secure, easy to update, cheap to run, fully customizable and should be able to easily handle the kind of traffic a new site is likely to get. If you need more power, just shutdown your EC2 instances and upgrade to a larger instance type. Or get fancy by spinning up more webservers and using the load balancer to route requests among them.

Anyway, thanks for making it this far! If you've got any suggestions for how to do anything in this guide better, please leave a comment or a pull request! And if you build any custom Chef code for your own deployment, please consider contributing it back to this guide or to the official [application_python](https://github.com/opscode-cookbooks/application_python) cookbook.

And if you enjoy this kind of material, consider [following me on Twitter](http://www.twitter.com/rogueleaderr) or [subscribing to my newsletter](http://eepurl.com/GeOqP).

###Notes
[1]<a href id="note_algo"></a> And Python has existing libraries that implement nearly any algorithm better than I could anyway.

[2]<a href id="note_devops"></a> I'll
try to be gentle but won't simplify where doing so would hurt the
quality of the ultimate deployment. If you
don't know what a load balancer or an SSH key is, you're going to have
a hard time following along. But Google can help you with that. Don't worry, I'll be here when you get back.

[3]<a href id="cred_3"></a> You *can* run Postgres on the same VM, but putting it on a
separate box will avoid resource contention and make your app more scalable. You also can run nginx and celery on their own VM's which will make your site *super* scalable. But if you need this guide then you're probably not seeing enough traffic to make that worth the added complexity.

[4]<a href id="cred_3"></a> [More about WSGI](http://agiliq.com/blog/2013/07/basics-wsgi/)

[5]<a href id="note_docker"></a> But *you* should really consider writing a guide to deploying Django
using Docker so I can link to it.

[6]<a href id="note_2"></a> For development I enjoy [VirtualenvWrapper](http://virtualenvwrapper.readthedocs.org/en/latest/) which makes switching between venv's easy. But it installs venvs by default in a ~/Envs home directory and for deployment we want to keep as much as possible inside of one main project directory (to make everything easy to find.)

[7]<a href id="cred_2"></a> Hat tip to garnaat for
[his AWS recipe to setup an account with boto](https://github.com/garnaat/paws/blob/master/ec2_launch_instance.py)

[8]<a href id="cred_1"></a> Hat tip to Martha Kelly for [her post on using Fabric/Boto to deploy EC2](http://marthakelly.github.io/blog/2012/08/09/creating-an-ec2-instance-with-fabric-slash-boto/)

[9]<a href id="cred_4"></a> Chef/Django posts:

* ["Building a Django App Server with Chef, Eric Holscher"](http://ericholscher.com/blog/2010/nov/8/building-django-app-server-chef/)

* ["An Experiment With Chef Solo", jamiecurle]("https://github.com/jamiecurle/ubuntu-django-chef-solo-config")

* [Kate Heddleston's Talk on Chef at Pycon 2013](http://pyvideo.org/video/1756/chef-automating-web-application-infrastructure)

* [Honza's django-chef repo](https://github.com/honza/django-chef)

* [Noah Kantrowitz "Real World Django deployment using Chef](http://blip.tv/djangocon/real-world-django-deployment-using-chef-5572706)

[*]<a href id="note_salt"></a> Yes, there are other configuration automation tools. Puppet is widely used, but I find it slightly more confuing and it seems less popular in the Django community. There is also a tool called [Salt that's even in Python](http://saltstack.com/community.html). But Salt seems substantially less mature than Chef at this point.


###Glossary

<div id="gloss_ami">AMI</div> -- An "AMI" is an Amazon Machine Image, i.e. a re-loadable snapshot of a configured system.

<div id="#gloss_cli">CLI</div> -- command line interface. Amazon gives us a set of new command line "verbs" to control AWS.

<div id="gloss_ec2">EC2</div> -- Elastic Compute Cloud, Amazon's virtual server farm.

<div id="gloss_aws">AWS</div> -- Amazon Web Services, the umbrella of the many individual cloud services Amazon offers

<div id="gloss_dsl">DSL</div> -- Domain specific language. Aka a crazy mangled version of Ruby customized to describe service configuration.

<div id="gloss_ec2">VCS</div> -- Version control system, e.g. git or SVN or mercurial
###Bibliography
[Randall Degges rants on deployment](http://www.rdegges.com/deploying-django/)

[Rob Golding on deploying Django](http://www.robgolding.com/blog/2011/11/12/django-in-production-part-1---the-stack/)

[Aqiliq on deploying Django on Docker](http://agiliq.com/blog/2013/06/deploying-django-using-docker/)

[How to use Knife-Solo and Knife-Solo\_data\_bags](http://distinctplace.com/infrastructure/2013/08/04/secure-data-bag-items-with-chef-solo/)
