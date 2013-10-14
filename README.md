#Django in Production - The Definitely Definitive Guide


### Like this guide but don't want to actually read it? Hire me to do it for you.

## Overview

**By the end of this guide, you should be have a (simple), actually deployed
  Django website accessible at a public IP.** So anyone in the world will be
  able to visit "www.yourapp.com" and see a page that says "Hello World!"

You'll go through the following steps:

1. [Setting up a host server for your webserver and your database](#servers).
2. [Installing and configuring the services your site will need](#services).
3. [Automating deployment of your code](#code).
4. [Setting up monitoring so your site doesn't explode](#monitoring)

##Why This Guide Is Needed

Over the last two years, I've taught myself to program in order to
build my startup [LinerNotes.com](http://www.linernotes.com). I
started out expecting that the hardest part would be getting my head
around the sophisticated algorithmic logic of programming. To my
surprise, I've actually had to do very little algorithmic work. And Python has existing
libraries that implement nearly any algorithm better than I could anyway.

Instead, the hardest part has been getting proficient at using the
*many* different tools in the programmer's utility belt. From emacs to
gunicorn, building a real project requires dozens of different
tools. Theoretically, one can *a priori* reason through a red-black
tree. But there's just no way to learn emacs without the reading the
manual. LinerNotes is actually a lot more complicated under the hood
than it is on the surface, so I've had to read quite a lot of
manuals.

The point of this guide is to save you some of that trouble. Sometimes trouble is good. Struggling to design and implement an API builds programming acumen. Struggling to
configure nginx is just a waste of time. I've found many partial
guides to parts of Django deployment but haven't found any single,
recently updated resource that lays out the **simple, Pythonic way of
deploying a Django site in production**. This post will give you an actual production-ready
deployment setup. But it *won't* introduce you to basic DevOps 101 concepts. I'll
try to be gentle but won't simplify where doing so would hurt the
quality of the ultimate deployment.

I'm definitely not the most qualified person to write this post, but
it looks like I'm the only one dumb enough to try. If you've got
suggestions about how any part of this process could be better,
*please* comment (or even better submit a pull request to the Github repo) and I'll update the guide as approriate.

##Overview of the Final Architecture

Now this site is just a "hello world" app, but this is going to be the most well-implemented, stable, and scalable
"hello world" application on the whole world wide web. Here's a diagram of how
your final architecture will look:

![Architecture Diagram](https://raw.github.com/rogueleaderr/definitive_guide_to_django_deployment/master/django_deployment_diagram.png)

Basically, users send HTTP requests to your server, which are intercepted and
routed by the nginx webserver program. Requests for dynamic content will be routed to
your [WSGI](http://wsgi.readthedocs.org/en/latest/what.html)[[1]](#cred_3) server (Gunicorn) and requests for static content will be served
directly off the server's file system. Gunicorn has a few helpers, memcached and celery,
which respectively offer a cache for repetitive tasks and an asynchronous queue
for long-running tasks.

We've also got our Postgres database (for all your lovely models) which we run on a
separate EC2 server. You *can* run Postgres on the same VM, but putting it on a
separate box will avoid resource contention and make your app more scalable.

See [below](#services) for a more detailed description of what each component
actually does.



##<a id="servers"></a>Set Up the "Physical" Servers

###Set up AWS/EC2

Since this guide is trying to get you to an actual publicly accessible site,
we're going to go ahead and build our site on the smallest, freest Amazon Elastic Compute Cloud
(EC2) instance available, the trusty "micro". If you don't want to use
EC2, you can set up a local virtual machine on your laptop using 
[Vagrant](http://www.vagrantup.com/). I'm intrigued by the
[Docker project](https://www.docker.io/) that claims to allow deployment of
whole application components in platform agnostic "containers." But Docker
itself says it's not stable enough for production; who am I to
disagree?[[2]](#note_1)

Anyway, we're going to use EC2 to set up the smallest possible host for our webserver and another
one for our database.

For this tutorial, you'll need an existing EC2 account. There are [many tutorials on setting up an account](http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/get-set-up-for-amazon-ec2.html) so I'm not going to walk you through the account setup.

Python has a very nice library called [boto](https://github.com/boto/boto) for administering AWS
from within code. And another nice tool called [Fabric](http://docs.fabfile.org/en/1.7/) for creating
command-line directives that execute Python code that can itself execute
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
install into a virtualenv (but won't track wtih git):[[3]](#note_2)

    virtualenv django_deployment_env
    source django_deployment_env/bin/activate
    # install all our neccesary dependencies from a requirements file
    pip install -r requirements.txt
    # or, for educational purposes, individually
    pip install boto
    pip install fabric
    pip install awscli

The github repo includes a fabfile.py[[4]](#cred_1) which provides all the
commandline directives we'll need. But fabfiles are pretty intuitive
to read, so try to follow along with what each command is doing.

First, we need to set up Amazon Web Services (AWS) credentials for boto to use. In keeping
with the principles of the [Twelve Factor App](http://12factor.net/)
we store configuration either in environment variables or in config
files which are not tracked by VCS.

    echo '
    aws_access_key_id: <YOUR KEY HERE>
    aws_secret_access_key: <YOUR SECRET KEY HERE>
    region: "<YOUR REGION HERE, e.g. us-east-1>"
    key_name: hello_world_key
    key_dir: "~/.ec2"
    group_name: hello_world_group
    ssh_port: 22
    ubuntu_lts_ami: "ami-d0f89fb9"' > aws.cfg
    echo "aws.cfg" >> .gitignore

(An "AMI" is an Amazon Machine Image, and the one we've chosen corresponds to a
"free-tier" eligible Ubuntu image.)

While we're at it, let's create a config file that will let you use
the AWS command line interface (CLI) directly:

    mkdir ~/.aws
    echo '
    aws_access_key_id = <YOUR KEY HERE>
    aws_secret_access_key = <YOUR SECRET KEY HERE>
    region = <YOUR REGION HERE, e.g. us-east-1>' > ~/.aws/config


Now we're going to use a Fabric directive to setup our AWS account[[5]](#cred_2) by:

1. Configuring a keypair ssh key that will let us log in to our servers
2. Setup a security group that defines access rules to our servers

To use our first fabric directive and setup our AWS account, go to the directory where our fabfile lives and
do

    fab setup_aws_account

###Launch EC2 Servers

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


##<a id="services"></a>Install and Configure Your Services

###Understand the services
Our app is made up of a number of services that run
semi-independently:

**Gunicorn**: Our WSGI webserver. Gunicorn receives HTTP requests fowarded to it from nginx, executes
  our Django code to produce a response, and returns the response which nginx transmits back to the client.
  
**Nginx**: Our
  "[reverse proxy](http://en.wikipedia.org/wiki/Reverse_proxy)"
  server. Nginx takes requests from the open internet and decides
  whether they should be passed to Gunicorn, served a static file,
  served a "Gunicorn is down" error page, or even blocked (e.g. to prevent denial-of-service
  requests.)

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
domain specific language (DSL) for expressing configuration. And it
also provides a whole system (Chef server) for controlling the
configuration of remote servers (a.k.a. "nodes") from a central location. The DSL is
unavoidable, but we can make things a bit simpler by using "Chef Solo", a stripped down version of Chef that does away with the whole central server and leaves us with
just a single script that we run on our remote servers to bootstrap our
configuration.

(Hat tip to several authors for blog posts about using Chef for Django[[6]](#cred_4))

####Set up Chef

First, install Ruby:

    #brew install rbenv (the virtualenv equivalent)
    echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.zshrc # or .bashrc
    echo 'eval "$(rbenv init -)"' >> ~/.zshrc # or .bashrc
    rbenv install 1.9.3-p448
    rbenv global 1.9.3-p448
    #install bundler, the pip equivalent
    gem install bundler

Install some tools that simplify working with Chef ([Knife Solo](https://github.com/matschaffer/knife-solo), [Knife Solo Data Bag](https://github.com/thbishop/knife-solo_data_bag), [Berkshelf](http://berkshelf.com/), and [Knife-solo\_data\_bag](https://github.com/thbishop/knife-solo_data_bag):

    # Install all the gems in the file "Gemfile"
    bundler install
    # Ruby requires rehashing to use command line options
    rbenv rehash

Use Berkshelf to install the cookbooks we'll need:

    cd chef_files
    # tell Berkshelf to install cookbooks into our folder instead of ~/.berkshelf
    export BERKSHELF_PATH=chef_files
    berks install
    cd ..

####Wait, a complicated ruby tool? Really?

Yes, really. Despite being in Ruby[[7]](#note_5), Chef some great advantages that make it worth learning (at least enough to follow this guide.)

1. It lets us fully automate our deployment. We only need to edit *one* configuration file and run two commands and our *entire stack* configures itself automatically. And if your servers all die you can redeploy from scratch with the same two commands (assuming you backed up your database).
2. It lets us lock the versions for all of our dependencies. Every package installed by this process has its version explicitly specified. So this guide/process may become dated but it should continue to at least basically work for a long time.
3. It lets us stand on the shoulders of giants. Opscode (the creators of Chef) and some great OSS people have put a lot of time into creating ready-to-use Chef "cookbooks" for nearly all oru needs. Remember, *DRPWKBTY* (Don't Repeat People Who Know Better Than You).

Okay, buckle up. We're going to need to talk a little about how Chef works. But it'll be worth it.

At the root, Chef is made up of small Ruby scripts called *recipes* that express
configuration. Chef *declares* configuration rather than executing a
series of steps (the way Fabric does). A recipe is supposed to describe all the resources that
are available on a server (rather than just invoking installation
commands.) If a resource is missing when a recipe is run, Chef will
try to figure out how to install that resource. Recipes are
(supposed to be) *idempotent*, meaning that if you run a recipe and
then run it again then the second run will have no effects.

But which recipes to run? Chef uses *cookbooks* that
group together recipes for deploying a specific tool (e.g. "the git
cookbook"). And Chef has a concept called "roles" that let you specify
which cookbooks should be used on a given server. So for example, we
can define a "webserver" role and tell Chef to use the "git", "nginx"
and "django" cookbooks. Opscode (the makers of Chef) provide a bunch
of pre-packaged and (usually well maintained) cookbooks for common
tools like git. And although Chef cookbooks can get quite complicated, they are just code and so they can be version controlled with git. These version controlled cookbooks are what we installed with Berkshelf above.

####Chef, make me a serve-which

We're going to have two nodes, a webserver and a database.So we'll have three roles:

1. base.rb (common configuration that both will need, like apt and git)
2. application_server.rb (webserver configuration)
3. database.rb (database configuration)

The role definitions live in `chef_files/roles`. Now we just need to tell Chef which roles apply to which nodes, and we do that in our chef\_files/nodes folder in files named "{node name}\_node.json".

Any production Django installation is going to have some sensitive
values (e.g. database passwords). Chef has a construct called *data
bags* for isolating and storing sensitive information. And these bags
can even be encrypted so they can be stored in a version control
system (VCS). Knife solo lets us create a databag and encrypt
it. Fabric will automatically upload our databags to the server where
they'll be accessible to our Chef solo recipe.

First, we need an encryption key (which we will *NOT* store in Github):

    cd chef_files
    openssl rand -base64 512 > data_bag_key
    cd ..
    # if you aren't using my repo's .gitingore, add the key
    echo "chef_files/data_bag_key" >> .gitignore

Open `settings.json` and set your database password and IP (plus whatever other private settings you might want). It should look something like:

    {
    "id": "config_1",
    "POSTGRES_PASS": "postgres",
    "DEBUG": "False",
    "DOMAIN": "deployment_example_project.com",
    "APP_NAME": "deployment_example_project",
    "DATABASE_NAME": "deployment_example_project",
    "REPO": "django_deployment_example_project",
    "GITHUB_USER": "rogueleaderr",
    "DATABASE_IP": "ec2-54-221-3-78.compute-1.amazonaws.com"
    }

Now we can use the knife-solo to create an encrypted data bag:

    cd chef_files
    knife solo data bag create config config_1 --json-file ../settings.json
    cd ..


Make sure to add "gunicorn" and "djcelery" to your installed apps.


Now we're going to use Fabric to tell Chef to bootstrap first out database and then our webserver. Do:

    fab bootstrap:database
    fab bootstrap:webserver

This will:

1. Install Chef
2. Tell Chef to configure the server

###Make it public.

If Chef runs all the way through without error (as it should) you'll now have a 'Hello World' site accessible by opening your browser and visiting the "public DNS" of your site (which you can find from the EC2 management console or by doing `cat fab_hosts/webserver.txt`. But you probably don't want visitors to have to type in "103.32.blah-blah.ec2.blah-blah". You want them to just visit "myapp.com" and to do that you'll need to visit your domain registrar (e.g. GoDaddy or Netfirms) and change your **A-Record** to point to the IP of your webserver (which can also be gotten from the EC2 console or by doing):

    ec2-describe-instances | fgrep `cat fab_hosts/webserver.txt` | cut -f17

Domain registrars vary greatly on how to change the A-record so check your registrar's instructions.



open port 80 to world and 5432 to hello_world_group



http://berkshelf.com/


##<a id="code"></a>Deploy Your Code

Just commit your repo and do

    git push origin master

Back in the deployment guide folder, do:

    fab deploy:webserver
    

##<a id="monitoring"></a>Set Up Monitoring

That's a story...for next time. Also backup.


Datadog Monitoring
------

I use a cool service called Datadog that makes pretty metric dashboards. It also sends an
alert if there's no CPU activity from the webserver or the database (probably meaning the
EC2 servers are down.)

You can [look at it here]()

Notifications / PagerDuty
-------------

*PagerDuty* is a website that will call or email you if something goes wrong with a
 server. I've configured it to email/SMS you if anything goes wrong with the site. If you
 get a notication, check to make sure that it's not a false alarm, fix the problem (if
 needed) and reply to PagerDuty that you resolved the issue.

Django also also automatically emits error emails, which I:

1) route to PagerDuty so it automatically sets up an "incident" and SMS's you
2) sends an email to you with the details of the error

Occasionally these emails are for non-serious issues but there's no easy way to
filter. Below I've listed a few "non-problems" that you can safely ignore.


##Debugging:

Instructions by Service:
----

###Nginx

Nginx is the proxy server that routes HTTP traffic. In 6 months, it has never once gone
down for me. It should start automatically if the webserver restarts.

If you need to start/restart nginx, log in to the webserver and do:

    sudo service nginx restart

If nginx misbehaves, logs are at:

    /var/log/nginx/

If, for some reason, you need to edit the nginx configuration file it's at:

    sudo emacs /etc/nginx/sites-available/hello.conf

###Memcached

Memcached is also a service and starts automatically if the webserver restarts. The site
should also continue to function if it dies (just be slow). Caching issues can sometimes
cause weird page content, so if something seems unusually bizarre try flushing the cache
by restarting memcached:

    sudo service restart memcached

Memcached is pretty fire and forget...since it's in memory it's theoretically possible it
could fill up and exhaust the memory on the webserver (I don't have a size cap and ttl's
are very long) but that has never happened so far. If it does, just reset memcached and it
will clear itself out.


###RabbitMQ

Another service that's started automatically. I have literally never had to interact
directly with it. But if can also be restarted by

    sudo service restart rabbitmq


#### To start Gunicorn/Celery:

Gunicorn and the Celery Workers are controlled by *Supervisor*, which is a Linux process runner/controller. Supervisor starts
Gunicorn and Celery when the EC2 server starts and will automatically restart them if
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


**WHERE IS LOG DIR?**

I keep a [GNU screen](http://www.gnu.org/software/screen/) active in the log directory so
I can get there quickly if I need to. You can get there with

    screen -r 26334.pts-3.ip-10-145-149-233

###Postgres

Postgres is a very stable program but my configuration can be a bit touchy. It's probably
the most likely component to give you trouble (and sadly the site becomes totally
non-operational if it goes down.)

Postgres runs as a service so if you need to restart it (try not to need to do this) you
can do:

    sudo service postgresql restart

The disk can also fill (especially if something gets weird with the logging.) To check disk space:

    df -h

If a disk is 99% full, find big files using

    find / -type f -size +10M -exec ls -l {} \;

EC2 instances all have "instance store" disks on /mnt, so you can copy obviously
suspicious files onto the instance store and let me sort it out later (please make a note
of what you move and from/to where).

If that's not enough, check the logs for the service (log dirs should be listed for all
key components above) and see if there is an obvious problem.


Static Files
-----------

All static files (JS, CSS, images) are served out of Amazon S3 from the
"linernotes\_static\_public" bucket. If the site suddenly loses all of it's CSS, check
that S3 is working and that the static files/bucket are in place and working. If Amazon
for some reason changes the S3 paths, the app defines the static paths in

    /var/www/hello-env/hello/hello//hello/settings/base.py

Under the "STATIC_ROOT" variable.

If you need to modify static files (e.g. edit JS), you can upload new static files to S3
by running

    python manage.py collectstatic

From the project root directory (wth a virtualenv enabled) or just run the "git\_to\_prod"
script which includes static collection as a step.





US PG BOUNCER

##Bibliography
[Randall Degges rants on deployment](http://www.rdegges.com/deploying-django/)

[Rob Golding on deploying Django](http://www.robgolding.com/blog/2011/11/12/django-in-production-part-1---the-stack/)

[Aqiliq on deploying Django on Docker](http://agiliq.com/blog/2013/06/deploying-django-using-docker/)





[How to use Knife-Solo and Knife-Solo_data_bags](http://distinctplace.com/infrastructure/2013/08/04/secure-data-bag-items-with-chef-solo/)

##Notes
[1]<a href id="note_1"></a> (But *you* should really consider writing a guide to deploying Django
using Docker so I can link to it.)

[2]<a href id="note_2"></a>For development I enjoy [VirtualenvWrapper](http://virtualenvwrapper.readthedocs.org/en/latest/) which makes switching between venv's easy. But it installs venvs by default in a ~/Envs home directory and for deployment we want to keep as much as possible inside of one main project directory (to make everything easy to find.)

[7]<a href id="note_2"></a>Yes, there are other configuration automation tools. Puppet is widely used, but I find it slightly more confuing and it seems less popular in the Django community. There is a tool called [Salt that's even in Python](http://saltstack.com/community.html)). But Salt seems substantially less mature than Chef at this point.

[3]<a href id="cred_1"></a> Hat tip to Martha Kelly for [her post on using Fabric/Boto to deploy EC2](http://marthakelly.github.io/blog/2012/08/09/creating-an-ec2-instance-with-fabric-slash-boto/)

[4]<a href id="cred_2"></a> Hat tip to garnaat for
[his AWS recipe to setup an account with boto](https://github.com/garnaat/paws/blob/master/ec2_launch_instance.py)

[5]<a href id="cred_3"></a> [More about WSGI](http://agiliq.com/blog/2013/07/basics-wsgi/)

[6]<a href id="cred_4"></a> ["Building a Django App Server with Chef, Eric Holscher"](http://ericholscher.com/blog/2010/nov/8/building-django-app-server-chef/); ["An Experiment With Chef Solo", jamiecurle]("https://github.com/jamiecurle/ubuntu-django-chef-solo-config"); [Kate Heddleston's Talk on Chef at Pycon 2013](http://pyvideo.org/video/1756/chef-automating-web-application-infrastructure); [Honza's django-chef repo](https://github.com/honza/django-chef); [Noah Kantrowitz "Real World Django deployment using Chef](http://blip.tv/djangocon/real-world-django-deployment-using-chef-5572706)


add net.core.somaxconn=1024 to /etc/sysctl.conf

cache-machine
