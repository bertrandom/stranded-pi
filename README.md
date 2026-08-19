# rpi-jc-ansible

Install Johnny Castaway on a Raspberry Pi using Ansible

## Installation

On Raspberry Pi:
```
sudo apt install ansible
```

Then run:
```
ansible-playbook -i inventory.yml main.yml -l pijohnny --ask-become-pass
```

## Notes

Tested on a Raspberry Pi 3 Model B Rev 1.2 running Raspberry Pi OS Lite 64-bit Trixie