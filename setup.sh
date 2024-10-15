#! /bin/bash

sudo apt update
sudo apt install perl -y
sudo perl -MCPAN -e "install Parse::Win32Registry"