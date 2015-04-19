FROM ubuntu:15.04

# This stops apt from presenting interactive prompts when installing apps that
# would normally ask for them. Alternatively, check out debconf-set-selections.
ENV DEBIAN_FRONTEND=noninteractive

# groff is needed by the awscli pip package.
# rsync is needed by knife.
# zlib1g-dev is needed by the gem dependency chain.
RUN apt-get update && apt-get --yes --quiet install \
bundler \
groff \
python \
python-dev \
python-pip \
python-virtualenv \
rbenv \
rsync \
ruby-dev \
ssh \
vim \
zlib1g-dev

RUN mkdir -p /project/django_deployment
WORKDIR /project/django_deployment

# Install ruby gems
RUN echo "gem: --no-ri --no-rdoc" > ~/.gemrc
ADD ./Gemfile Gemfile
RUN bundler install

# Install Python project to a virtualenv that will activate when we log in.
ADD ./requirements.txt requirements.txt
RUN virtualenv /project/env
RUN echo "source /project/env/bin/activate" > ~/.bashrc
RUN /project/env/bin/pip --quiet install --requirement requirements.txt
