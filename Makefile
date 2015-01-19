DOKKU_VERSION = master

SSHCOMMAND_URL ?= https://raw.github.com/progrium/sshcommand/master/sshcommand
PLUGINHOOK_URL ?= https://s3.amazonaws.com/progrium-pluginhook/pluginhook_0.1.0_amd64.deb
STACK_URL ?= https://github.com/sunsong/buildstep.git
PREBUILT_STACK_URL ?= https://github.com/progrium/buildstep/releases/download/2014-12-16/2014-12-16_42bd9f4aab.tar.gz
PLUGINS_PATH ?= /var/lib/dokku/plugins
TRUSTY_REPOSITORY_URL ?= http://cn.archive.ubuntu.com/ubuntu/
CEDARISH_URL ?= https://github.com/sunsong/cedarish.git

# If the first argument is "vagrant-dokku"...
ifeq (vagrant-dokku,$(firstword $(MAKECMDGOALS)))
  # use the rest as arguments for "vagrant-dokku"
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  # ...and turn them into do-nothing targets
  $(eval $(RUN_ARGS):;@:)
endif

.PHONY: all install copyfiles version plugins dependencies sshcommand pluginhook docker aufs stack count dokku-installer vagrant-acl-add vagrant-dokku

include tests.mk
include deb.mk

all:
	# Type "make install" to install.

install: dependencies stack copyfiles plugin-dependencies plugins version

release: deb-all package_cloud packer

package_cloud:
	package_cloud push dokku/dokku/ubuntu/trusty buildstep*.deb
	package_cloud push dokku/dokku/ubuntu/trusty sshcommand*.deb
	package_cloud push dokku/dokku/ubuntu/trusty pluginhook*.deb
	package_cloud push dokku/dokku/ubuntu/trusty rubygem*.deb
	package_cloud push dokku/dokku/ubuntu/trusty dokku*.deb

packer:
	packer build contrib/packer.json

copyfiles:
	cp dokku /usr/local/bin/dokku
	mkdir -p ${PLUGINS_PATH}
	find ${PLUGINS_PATH} -mindepth 2 -maxdepth 2 -name '.core' -printf '%h\0' | xargs -0 rm -Rf
	find plugins/ -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | while read plugin; do \
		rm -Rf ${PLUGINS_PATH}/$$plugin && \
		cp -R plugins/$$plugin ${PLUGINS_PATH} && \
		touch ${PLUGINS_PATH}/$$plugin/.core; \
		done
	$(MAKE) addman

addman:
	mkdir -p /usr/local/share/man/man1
	help2man -Nh help -v version -n "configure and get information from your dokku installation" -o /usr/local/share/man/man1/dokku.1 dokku
	mandb

version:
	git describe --tags > ~dokku/VERSION  2> /dev/null || echo '~${DOKKU_VERSION} ($(shell date -uIminutes))' > ~dokku/VERSION

plugin-dependencies: pluginhook
	dokku plugins-install-dependencies

plugins: pluginhook docker
	dokku plugins-install

dependencies: sshcommand pluginhook docker debootstrap create_base_image stack help2man

help2man:
	apt-get install -qq -y help2man

debootstrap:
	apt-get install debootstrap

create_base_image:
	docker images | grep -P "ubuntu-debootstrap\s+14.04" || (debootstrap trusty trusty ${TRUSTY_REPOSITORY_URL} && tar -C trusty -c . | docker import - ubuntu-debootstrap:14.04)
	docker images | grep -P "progrium/cedarish\s+cedar14" || (git clone ${CEDARISH_URL} /tmp/cedarish && cd /tmp/cedarish && make && cat release/darish-cedar14_v2.tar | docker import - progrium/cedarish:cedar14 && rm -rf /tmp/cedarish)

sshcommand:
	wget -qO /usr/local/bin/sshcommand ${SSHCOMMAND_URL}
	chmod +x /usr/local/bin/sshcommand
	sshcommand create dokku /usr/local/bin/dokku

pluginhook:
	wget -qO /tmp/pluginhook_0.1.0_amd64.deb ${PLUGINHOOK_URL}
	dpkg -i /tmp/pluginhook_0.1.0_amd64.deb

docker: aufs
	apt-get install -qq -y curl
	egrep -i "^docker" /etc/group || groupadd docker
	usermod -aG docker dokku
	curl --silent https://get.docker.io/gpg | apt-key add -
	echo deb http://get.docker.io/ubuntu docker main > /etc/apt/sources.list.d/docker.list
	apt-get update
ifdef DOCKER_VERSION
	apt-get install -qq -y lxc-docker-${DOCKER_VERSION}
else
	apt-get install -qq -y lxc-docker
endif
	sleep 2 # give docker a moment i guess

aufs:
ifndef CI
	lsmod | grep aufs || modprobe aufs || apt-get install -qq -y linux-image-extra-`uname -r` > /dev/null
endif

stack:
	@echo "Start building buildstep"
	@docker images | grep progrium/buildstep || (git clone ${STACK_URL} /tmp/buildstep && docker build -t progrium/buildstep /tmp/buildstep && rm -rf /tmp/buildstep)

count:
	@echo "Core lines:"
	@cat dokku bootstrap.sh | wc -l
	@echo "Plugin lines:"
	@find plugins -type f | xargs cat | wc -l
	@echo "Test lines:"
	@find tests -type f | xargs cat | wc -l

dokku-installer:
	apt-get install -qq -y ruby
	test -f /var/lib/dokku/.dokku-installer-created || gem install rack -v 1.5.2 --no-rdoc --no-ri
	test -f /var/lib/dokku/.dokku-installer-created || gem install rack-protection -v 1.5.3 --no-rdoc --no-ri
	test -f /var/lib/dokku/.dokku-installer-created || gem install sinatra -v 1.4.5 --no-rdoc --no-ri
	test -f /var/lib/dokku/.dokku-installer-created || gem install tilt -v 1.4.1 --no-rdoc --no-ri
	test -f /var/lib/dokku/.dokku-installer-created || ruby /root/dokku/contrib/dokku-installer.rb onboot
	test -f /var/lib/dokku/.dokku-installer-created || service dokku-installer start
	test -f /var/lib/dokku/.dokku-installer-created || service nginx reload
	test -f /var/lib/dokku/.dokku-installer-created || touch /var/lib/dokku/.dokku-installer-created

vagrant-acl-add:
	vagrant ssh -- sudo sshcommand acl-add dokku $(USER)

vagrant-dokku:
	vagrant ssh -- "sudo -H -u root bash -c 'dokku $(RUN_ARGS)'"

