#! /bin/bash

# Install Perl
# sudo apt update
# sudo apt install perl -y

# Install Parse:Win32Registry Perl library
sudo perl -MCPAN -e "install Parse::Win32Registry"

# Clone linux_regripper repository
if [ -d "/opt/linux_regripper" ]; then
    echo "linux_regripper already cloned, moving on..."
else
    cd /opt
    git clone https://github.com/glowbase/linux_regripper.git
fi

chmod -R o+rx /opt/linux_regripper

# Add alias for regripper
echo "alias rr='/opt/linux_regripper/rip.pl'" >> ~/.bashrc
source ~/.bashrc