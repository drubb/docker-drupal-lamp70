FROM ubuntu:16.04
MAINTAINER Boris Böhne <info@drubb.de>

#
# Step 1: Installation
#

# Build argument for debian frontend
ARG DEBIAN_FRONTEND=noninteractive

# Expose web root as volume
VOLUME ["/var/www"]

# Add additional repostories needed later
RUN echo "deb http://ppa.launchpad.net/git-core/ppa/ubuntu trusty main" >> /etc/apt/sources.list
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E1DF1F24

# Update repositories cache and distribution
RUN apt-get -qq update && apt-get -qqy upgrade

# Install some basic tools needed for deployment
RUN apt-get -yqq install apt-utils sudo build-essential debconf-utils locales curl wget unzip patch dkms supervisor

# Add the docker user
ENV HOME /home/docker
RUN useradd docker && passwd -d docker && adduser docker sudo
RUN mkdir -p $HOME && chown -R docker:docker $HOME

# Install SSH client
RUN apt-get -yqq install openssh-client

# Install ssmtp MTA
RUN apt-get -yqq install ssmtp

# Install Apache web server
RUN apt-get -yqq install apache2

# Install MySQL server and save initial configuration
RUN echo "mysql-server mysql-server/root_password password root" | debconf-set-selections
RUN echo "mysql-server mysql-server/root_password_again password root" | debconf-set-selections
RUN apt-get -yqq install mysql-server
RUN service mysql start && service mysql stop && tar cpPzf /mysql.tar.gz /var/lib/mysql

# Install PHP5 with Xdebug and other modules
RUN apt-get -yqq install libapache2-mod-php php-mcrypt php-dev php-mysql php-curl php-gd php-intl php-xdebug php-mbstring

# Install PEAR package manager
RUN apt-get -yqq install php-pear && pear channel-update pear.php.net && pear upgrade-all

# Install PECL package manager
RUN apt-get -yqq install libpcre3-dev

# Install PECL uploadprogress extension
RUN pecl install uploadprogress

# Install memcached service
RUN apt-get -yqq install memcached php-memcached

# Install GIT (latest version)
RUN apt-get -yqq install git

# Install composer (latest version)
RUN curl -sS https://getcomposer.org/installer | php && mv composer.phar /usr/local/bin/composer

# Install drush and drupal console (latest stables)
USER docker
RUN sudo composer global require drush/drush drupal/console
USER root

# Install PhpMyAdmin (latest version)
RUN wget -q -O phpmyadmin.zip https://github.com/phpmyadmin/phpmyadmin/archive/STABLE.zip && unzip -qq phpmyadmin.zip
RUN rm phpmyadmin.zip && mv phpmyadmin-STABLE /opt/phpmyadmin

# Install zsh / OH-MY-ZSH
RUN apt-get -yqq install zsh && git clone git://github.com/robbyrussell/oh-my-zsh.git $HOME/.oh-my-zsh

# Install PROST drupal deployment script, see https://www.drupal.org/sandbox/axroth/1668300
RUN git clone --branch master http://git.drupal.org/sandbox/axroth/1668300.git /tmp/prost
RUN chmod +x /tmp/prost/install.sh

# Install some useful cli tools
RUN apt-get -yqq install mc htop vim

# Cleanup some things
RUN apt-get -yqq autoremove; apt-get -yqq autoclean; apt-get clean

# Expose some ports to the host system (web server, MySQL, Xdebug)
EXPOSE 80 3306 9000

#
# Step 2: Configuration
#

# Localization
RUN dpkg-reconfigure locales && locale-gen de_DE.UTF-8 && /usr/sbin/update-locale LANG=de_DE.UTF-8
ENV LC_ALL de_DE.UTF-8

# Set timezone
RUN echo "Europe/Berlin" > /etc/timezone && dpkg-reconfigure -f noninteractive tzdata

# Add apache web server configuration file
ADD config/httpd.conf /etc/apache2/conf-available/httpd.conf

# Configure needed apache modules, disable default sites and enable custom site
RUN a2enmod rewrite headers expires && a2dismod status && a2dissite 000-default && a2enconf httpd

# Add additional php configuration file
ADD config/php.ini /etc/php/7.0/mods-available/php.ini
RUN phpenmod php

# Add additional mysql configuration file
ADD config/mysql.cnf /etc/mysql/conf.d/mysql.cnf

# Add memcached configuration file
ADD config/memcached.conf /etc/memcached.conf

# Add ssmtp configuration file
ADD config/ssmtp.conf /etc/ssmtp/ssmtp.conf

# Add phpmyadmin configuration file
ADD config/config.inc.php /opt/phpmyadmin/config.inc.php

# Add git global configuration files
ADD config/.gitconfig $HOME/.gitconfig
ADD config/.gitignore $HOME/.gitignore

# Add drush global configuration file
ADD config/drushrc.php $HOME/.drush/drushrc.php

# Add ocp status script
RUN mkdir /opt/ocp && wget -O /opt/ocp/ocp.php https://gist.githubusercontent.com/ck-on/4959032/raw

# Add zsh configuration
ADD config/.zshrc $HOME/.zshrc

# Configure PROST drupal deployment script
RUN chown docker:docker $HOME/.zshrc
USER docker
ENV SHELL /bin/zsh
RUN export PATH="$HOME/.composer/vendor/bin:$PATH" && cd /tmp/prost && ./install.sh -noupdate $HOME/.prost
USER root
RUN rm -rf /tmp/prost

# ADD ssh keys needed for connections to external servers
ADD .ssh $HOME/.ssh
RUN echo "    IdentityFile ~/.ssh/id_rsa" >> /etc/ssh/ssh_config

# Add startup script
ADD startup.sh $HOME/startup.sh

# Supervisor configuration
ADD config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Entry point for the container
RUN chown -R docker:docker $HOME && chmod +x $HOME/startup.sh
USER docker
ENV SHELL /bin/zsh
WORKDIR /var/www
CMD ["/bin/bash", "-c", "$HOME/startup.sh"]
