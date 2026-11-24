Dotfiles for light weight hosts and networks with low resources.
Should have been named thin-conf.git. 
But think of it as the crashbang config, that was setup on a chromebook by chance. Or vice versa. Whatever.

## Usage
See main Bash harness and on/in-line "help"...

Try out the seeds and preconfigured compositions, run it like:
```bash
PATH+=:$PWD/tool/bash/exec
uc-vm.bash typeset cb-headless > run-cb-headless.bash
bash ./run-cb-headless.bash
```

## Compositions
Script `uc-vm.bash` is for running, testing this repo with QEMU provisioned guests.
Current preset compositions are:

- 9front - simple Plan 9 graphical setup using the port, just to play with it initially
- bl-boron - current (or old) customized i3 desktop
- cb-headless - debian netinst

## Status
Old desktop setup was BunsenLabs boron, but need to move on. Try BL carbon 1.
Or just do cloud-init enhanced deb netinst...

So work also on profile variants, different types headless and specific forms of graphical boxes, tablets and panels. Etc. etc.

See doc/CB_CONF.md for more on included devices.
Some of the classes covered will include their own power charge, but that is not a criteria.
Just that they have network, and more peripherals and resources than a regular router.
