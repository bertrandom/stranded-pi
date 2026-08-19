## Installation

On Raspberry Pi:
```
sudo apt install ansible
```

Then run:

```
ansible-playbook -i inventory.yml main.yml -l pijohnny --ask-become-pass
```