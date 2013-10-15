import os, json
from tempfile import mkdtemp
from contextlib import contextmanager

from fabric.operations import put
from fabric.api import env, local, sudo, run, cd, prefix, task, settings, execute
from fabric.colors import green as _green, yellow as _yellow
from fabric.context_managers import hide, show, lcd
import boto
import boto.ec2
from config import Config
import time

# import configuration variables from untracked config file
aws_cfg = Config(open("aws.cfg"))
app_settings = json.load(open("settings.json"))
env.key_filename = os.path.expanduser(os.path.join(aws_cfg["key_dir"],
                                                   aws_cfg["key_name"] + ".pem"))


#-----FABRIC TASKS-----------

@task
def setup_aws_account():

    ec2 = connect_to_ec2()

    # Check to see if specified keypair already exists.
    # If we get an InvalidKeyPair.NotFound error back from EC2,
    # it means that it doesn't exist and we need to create it.
    try:
        key_name = aws_cfg["key_name"]
        key = ec2.get_all_key_pairs(keynames=[key_name])[0]
        print "key name {} already exists".format(key_name)
    except ec2.ResponseError, e:
        if e.code == 'InvalidKeyPair.NotFound':
            print 'Creating keypair: %s' % aws_cfg["key_name"]
            # Create an SSH key to use when logging into instances.
            key = ec2.create_key_pair(aws_cfg["key_name"])

            # Make sure the specified key_dir actually exists.
            # If not, create it.
            key_dir = aws_cfg["key_dir"]
            key_dir = os.path.expanduser(key_dir)
            key_dir = os.path.expandvars(key_dir)
            if not os.path.isdir(key_dir):
                os.mkdir(key_dir, 0700)

            # AWS will store the public key but the private key is
            # generated and returned and needs to be stored locally.
            # The save method will also chmod the file to protect
            # your private key.
            key.save(key_dir)
        else:
            raise

    # Check to see if specified security group already exists.
    # If we get an InvalidGroup.NotFound error back from EC2,
    # it means that it doesn't exist and we need to create it.
    try:
        group = ec2.get_all_security_groups(groupnames=[aws_cfg["group_name"]])[0]
    except ec2.ResponseError, e:
        if e.code == 'InvalidGroup.NotFound':
            print 'Creating Security Group: %s' % aws_cfg["group_name"]
            # Create a security group to control access to instance via SSH.
            group = ec2.create_security_group(aws_cfg["group_name"],
                                              'A group that allows SSH access')
        else:
            raise

    # Add a rule to the security group to authorize SSH traffic
    # on the specified port.
    for port in ["80", aws_cfg["ssh_port"]]:
        try:
            group.authorize('tcp', port, port, "0.0.0.0/0")
        except ec2.ResponseError, e:
            if e.code == 'InvalidPermission.Duplicate':
                print 'Security Group: %s already authorized' % aws_cfg["group_name"]
            else:
                raise

    # postgres authorization
    try:
        group.authorize('tcp', 5432, 5432, src_group=group)
    except ec2.ResponseError, e:
        if e.code == 'InvalidPermission.Duplicate':
            print 'Security Group: %s already authorized' % aws_cfg["group_name"]
        else:
            raise

@task
def create_instance(name, ami=aws_cfg["ubuntu_lts_ami"],
                    instance_type=aws_cfg["instance_type"],
                    key_name=aws_cfg["key_name"],
                    key_extension='.pem',
                    key_dir='~/.ec2',
                    group_name=aws_cfg["group_name"],
                    ssh_port=22,
                    cidr='0.0.0.0/0',
                    tag=None,
                    user_data=None,
                    cmd_shell=True,
                    login_user='ubuntu',
                    ssh_passwd=None):
    """
    Launch an instance and wait for it to start running.
    Returns a tuple consisting of the Instance object and the CmdShell
    object, if request, or None.

    ami        The ID of the Amazon Machine Image that this instance will
               be based on.  Default is a 64-bit Amazon Linux EBS image.

    instance_type The type of the instance.

    key_name   The name of the SSH Key used for logging into the instance.
               It will be created if it does not exist.

    key_extension The file extension for SSH private key files.

    key_dir    The path to the directory containing SSH private keys.
               This is usually ~/.ssh.

    group_name The name of the security group used to control access
               to the instance.  It will be created if it does not exist.

    ssh_port   The port number you want to use for SSH access (default 22).

    cidr       The CIDR block used to limit access to your instance.

    tag        A name that will be used to tag the instance so we can
               easily find it later.

    user_data  Data that will be passed to the newly started
               instance at launch and will be accessible via
               the metadata service running at http://169.254.169.254.

    cmd_shell  If true, a boto CmdShell object will be created and returned.
               This allows programmatic SSH access to the new instance.

    login_user The user name used when SSH'ing into new instance.  The
               default is 'ec2-user'

    ssh_passwd The password for your SSH key if it is encrypted with a
               passphrase.
    """

    print(_green("Started creating {}...".format(name)))
    print(_yellow("...Creating EC2 instance..."))

    conn = connect_to_ec2()

    try:
        key = conn.get_all_key_pairs(keynames=[key_name])[0]
        group = conn.get_all_security_groups(groupnames=[group_name])[0]
    except conn.ResponseError, e:
        setup_aws_account()

    reservation = conn.run_instances(ami,
        key_name=key_name,
        security_groups=[group_name],
        instance_type=instance_type)

    instance = reservation.instances[0]
    conn.create_tags([instance.id], {"Name":name})
    if tag:
        instance.add_tag(tag)
    while instance.state != u'running':
        print(_yellow("Instance state: %s" % instance.state))
        time.sleep(10)
        instance.update()

    print(_green("Instance state: %s" % instance.state))
    print(_green("Public dns: %s" % instance.public_dns_name))

    if raw_input("Add to ssh/config? (y/n) ").lower() == "y":
        ssh_slug = """
        Host {name}
        HostName {dns}
        Port 22
        User ubuntu
        IdentityFile {key_file_path}
        ForwardAgent yes
        """.format(name=name, dns=instance.public_dns_name, key_file_path=os.path.join(os.path.expanduser(key_dir),
            key_name + key_extension))

        ssh_config = open(os.path.expanduser("~/.ssh/config"), "a")
        ssh_config.write("\n{}\n".format(ssh_slug))
        ssh_config.close()

    f = open("fab_hosts/{}.txt".format(name), "w")
    f.write(instance.public_dns_name)
    f.close()
    return instance.public_dns_name


@task
def terminate_instance(name):
    """
    Terminates all servers with the given name
    """

    print(_green("Started terminating {}...".format(name)))

    conn = connect_to_ec2()
    filters = {"tag:Name": name}
    for reservation in conn.get_all_instances(filters=filters):
        for instance in reservation.instances:
            if "terminated" in str(instance._state):
                print "instance {} is already terminated".format(instance.id)
                continue
            else:
                print instance._state
            print (instance.id, instance.tags['Name'])
            if raw_input("terminate? (y/n) ").lower() == "y":
                print(_yellow("Terminating {}".format(instance.id)))
                conn.terminate_instances(instance_ids=[instance.id])
                print(_yellow("Terminated"))



@task
def bootstrap(name, no_install=False):
    """
    Bootstrap the specified server. Install chef then run chef solo.

    :param name: The name of the node to be bootstrapped
    :param no_install: Optionally skip the Chef installation
    since it takes time and is unneccesary after the first run
    :return:
    """

    print(_green("--BOOTSTRAPPING {}--".format(name)))
    f = open("fab_hosts/{}.txt".format(name))
    env.host_string = "ubuntu@{}".format(f.readline().strip())
    if not no_install:
        install_chef()
    run_chef(name)


@task
def deploy(name):
    """
    Bootstrap the specified server. Install chef then run chef solo.

    :param name: The name of the node to be bootstrapped
    :param no_install: Optionally skip the Chef installation
    since it takes time and is unneccesary after the first run
    :return:
    """

    print(_green("--DEPLOYING {}--".format(name)))
    f = open("fab_hosts/{}.txt".format(name))
    env.host_string = "ubuntu@{}".format(f.readline().strip())
    deploy_app(name)


@task
def restart():
    """
    Reload nginx/gunicorn
    """
    with settings(warn_only=True):
        sudo("supervisorctl restart {app_name}".format(app_name=app_settings["APP_NAME"]))
        sudo('/etc/init.d/nginx reload')


#----------HELPER FUNCTIONS-----------

@contextmanager
def _virtualenv():
    with prefix(env.activate):
        yield


def connect_to_ec2():
    """
    return a connection given credentials imported from config
    """
    return boto.ec2.connect_to_region(aws_cfg["region"],
    aws_access_key_id=aws_cfg["aws_access_key_id"],
    aws_secret_access_key=aws_cfg["aws_secret_access_key"])


def install_chef():
    """
    Install chef-solo on the server.
    """
    print(_yellow("--INSTALLING CHEF--"))
    local("knife solo prepare -i {key_file} {host}".format(key_file=env.key_filename,
                                                           host=env.host_string))


def run_chef(name):
    """
    Read configuration from the appropriate node file and bootstrap
    the node

    :param name:
    :return:
    """
    print(_yellow("--RUNNING CHEF--"))
    node = "./nodes/{name}_node.json".format(name=name)
    with lcd('chef_files'):
        local("knife solo cook -i {key_file} {host} {node}".format(key_file=env.key_filename,
                                                           host=env.host_string,
                                                           node=node))


def deploy_app(name):

    print(_yellow("--RUNNING CHEF--"))
    node = "./nodes/deploy_node.json".format(name=name)

    with lcd('chef_files'):
        try:
            # skip updating the Berkshelf cookbooks to save time
            os.rename("chef_files/Berksfile", "chef_files/hold_Berksfile")
            local("knife solo cook -i {key_file} {host} {node}".format(key_file=env.key_filename,
                                                           host=env.host_string,
                                                           node=node))
            restart()
        except Exception as e:
            print e
        finally:
            os.rename("chef_files/hold_Berksfile", "chef_files/Berksfile")
