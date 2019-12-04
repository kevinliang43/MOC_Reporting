#!/bin/bash

function inst {
    local typ="$1" # Get the type of install
    shift;
    for p in $@
    do
        if [ "$typ" == 'yum' ]; then
            echo "yum install $p"
            sudo yum -y install $p
        elif [ "$typ" == 'pip' ]; then
            echo "pip install $p"
            sudo pip install $p
        fi
        # If fail, Abort
        if [ $? -ne 0 ]; then
            echo "Install failed for $p - Abort"
            exit 1           
        fi
    done
}

function unix_command {
    $@
    if [ $? -ne 0 ]; then
        echo "Could not run $@ - Abort"
        exit 1
    fi
}

echo
echo "------------------------------------"
echo " This script will setup our dev env"
echo "------------------------------------"

# Enable EPEL Repo
unix_command sudo yum --enablerepo=extras install epel-release

# Python
inst yum python-pip python-devel python-dateutil gcc 

# Upgrade Pip
unix_command sudo pip install --upgrade pip

# Postgres
inst yum postgresql-devel postgresql-server postgresql-contrib

# Other
inst yum vim

# Pip Install
inst pip psycopg2 Flask petl
inst pip psycopg2
inst pip petl

