#!/usr/bin/env bash
# maintainer EricSong.s@foxmail.com

SERVER_HOST=https://s.jj-robot.com
SERVICE_ROOT=/etc/jjrobot-service
JJROBOTCTL=/usr/local/bin/jjrobotctl
CERTS_PATH=/var/lib/jjrobot/certs
DOCKER_COMPOSE_VERSION=1.22.0
GATEWAY=10.10.10.1
HOST_NAME=10.10.10.2

REGISTRY_ALIYUN=registry.cn-shenzhen.aliyuncs.com/jjrobot
DAEMON_IMAGE=${REGISTRY_ALIYUN}/jjrobotd

commandExists(){
    command -v "$@" > /dev/null 2>&1
}

commandExistsOrExit1(){
    commandExists $@
    if [[ $? -ne 0 ]]; then
        echo -e "[\\033[31;1mX\\033[0m] check command: \\033[96;1m$@\\033[0m not exists, install fail"
        exit 1
    fi
}

checkCode0OrExit1(){
    if [[ $? -ne 0 ]]; then
        echo -e "[\\033[31;1mX\\033[0m] \\033[96;1m$@\\033[0m"
        exit 1
    fi
}

installDockerCE(){
    commandExists docker
    if [[ $? -ne 0 ]]; then
        echo -ne "installing DockerCE"\\r
        apt-get install apt-transport-https ca-certificates gnupg2 software-properties-common -y
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        add-apt-repository \
           "deb [arch=amd64] https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu \
           $(lsb_release -cs) \
           stable"
        apt-get update
        apt-get install docker-ce -y
    fi

    commandExistsOrExit1 docker
    echo -ne "DockerCE installed"\\n
}

installBaseImages(){
    docker pull ${DAEMON_IMAGE} && \
    docker tag ${DAEMON_IMAGE} jjrobot/jjrobotd
    checkCode0OrExit1 "Daemon install error"
}

installDockerCompose(){
    commandExists docker-compose
    if [[ $? -ne 0 ]]; then
        echo -ne "installing DockerCompose"\\r
        addr=${SERVER_HOST}/install/docker-compose-`uname -s`-`uname -m`_${DOCKER_COMPOSE_VERSION}
        curl -fsSL ${addr} -o /usr/local/bin/docker-compose
        checkCode0OrExit1 "download docker-compose from oss fail"
        chmod +x /usr/local/bin/docker-compose
    fi

    commandExistsOrExit1 docker-compose
    echo -ne "DockerCompose installed"\\n
}

installJJRobotCtl(){
    echo -ne "installing JJRobotCtl"\\r

    curl -fsSL ${SERVER_HOST}/install/jjrobotctl > ${JJROBOTCTL}
    checkCode0OrExit1 "download jjrobotctl from oss fail"
    chmod +x ${JJROBOTCTL}

    echo -ne "JJRobotCtl installed"\\n
}

updateUdevRules(){
    echo -ne "downloading udev rules"\\r

    curl -fsSL ${SERVER_HOST}/install/99-jjrobot-vol-serial.rules > /etc/udev/rules.d/99-jjrobot-vol-serial.rules
    checkCode0OrExit1 "download udev rules from oss fail"
    udevadm control --reload
    udevadm trigger --action=add

    echo -ne "udev rules updated"\\n
}

checkCerts(){
    if [[ -d $1 ]]; then
        rm -rf $1
    fi

    if [[ ! -f $1 ]]; then
        touch $1
    fi
}

generatePemFiles(){
    echo -ne "generating pem files..."\\r

    mkdir -p ${CERTS_PATH}

    checkCerts "${CERTS_PATH}/fullchain.pem"
    checkCerts "${CERTS_PATH}/privkey.pem"

    if [[ ! -e ${CERTS_PATH}/key.pem ]] ; then
       openssl genrsa -out ${CERTS_PATH}/key.pem 2048
       openssl req -new -x509 -key ${CERTS_PATH}/key.pem -out ${CERTS_PATH}/public.pem -subj "/CN=jjrobot"
    fi

    echo -ne "pem files generated    DONE"\\n
}

dockerNetworkSetup(){
    echo -ne "setup docker network"\\r

    docker network ls |grep robotnet > /dev/null
        if [[ $? -eq 1 ]]; then
            docker network create robotnet
            checkCode0OrExit1 "create docker network fail"
        fi

    echo -ne "setup docker network    DONE"\\n
}

buildNetworkInterfaces(){
    cat << EOF | python3
#!/usr/bin/env python3

from string import Template


def get_net_names():
    with open('/proc/net/dev') as proc:
        lines = proc.readlines()
        lines = lines[2:]
        return [line.split(':')[0].strip() for line in lines]


def get_net_enp_eth_only(net_names):
    return list(filter(lambda name: name.lower().startswith('eth') or name.lower().startswith('enp'), net_names))


def sort_net_names(net_names):
    return sorted(net_names)


net_template = '''
# interfaces(5) file used by ifup(8) and ifdown(8)
auto lo
iface lo inet loopback
{net1}
auto {net0}
iface {net0} inet static
address 10.10.10.2
netmask 255.255.255.0
gateway 10.10.10.1
dns-nameservers 10.10.10.1
'''

net_boocax_template = '''
auto {net1}
iface {net1} inet static
address 192.168.10.2
netmask  255.255.255.0
'''


def network_interfaces_output(net_names):
    net_names = sort_net_names(net_names)
    net_names_length = len(net_names)
    if net_names_length == 0:
        raise IndexError('net name index should not be 0')
    else:
        kwargs = {
            'net0': net_names[0],
            'net1': ''
        }
        if net_names_length > 1:
            kwargs['net1'] = net_boocax_template.format(net1=net_names[1])

        out = net_template.format(**kwargs)
        return out


if __name__ == '__main__':
    nets = get_net_names()
    nets = get_net_enp_eth_only(nets)
    output = network_interfaces_output(nets)
    print(output)
EOF
}

networkInterfacesSetup(){
    echo -ne "setup system network interfaces"\\r

    dst=/etc/network/interfaces
    buildNetworkInterfaces | cat > ${dst}
    checkCode0OrExit1 "generate /etc/network/interfaces fail"
    cat ${dst}

    echo -ne "setup system network interfaces    DONE"\\n
}

setupNetwork(){
    dockerNetworkSetup
    networkInterfacesSetup
}

setupLoader(){
    loader="UNKNOWN"

    echo -ne "setup system loader..."\\r

    trusty_target=/etc/init.d/jjrobotd
    xenial_target=/etc/systemd/system/jjrobotd.service
    lsb_release -c | grep trusty > /dev/null
    if [[ $? = 0 ]]; then
        loader="trusty"
        curl -fsSL ${SERVER_HOST}/install/jjrobotd_trusty > ${trusty_target}
        checkCode0OrExit1 "download trusty loader from oss fail"
        chmod +x ${trusty_target} && \
            update-rc.d jjrobotd defaults
    else
        loader="xenial"
        curl -fsSL ${SERVER_HOST}/install/jjrobotd_service_xenial > ${xenial_target}
        checkCode0OrExit1 "download xenial loader from oss fail"
        chmod +x ${xenial_target} && \
            systemctl enable jjrobotd.service
    fi

    checkCode0OrExit1 "setup system loader ${loader} fail"
    echo -ne "setup system loader trusty    DONE"\\n
}

install(){
    installDockerCE
    installBaseImages
    installDockerCompose
    installJJRobotCtl
    updateUdevRules
    generatePemFiles
    setupNetwork
    setupLoader
}


case "$1" in
    install)
        installxc
    ;;
    network)
        setupNetwork
    ;;
    *)
    echo "Usage: $0 {install|network}"
esac
