Dotfiles for light weight hosts and networks with low resources.

The `uc-vm.bash` script is development harnaess for writing and testing this repo using QEMU provisioned guests.
The configured compositions are:

- 9front - simple plan 9 graphical setup
- bl-boron - current (or old) customized i3 desktop
- cb-headless - debian netinst

Old desktop setup was BunsenLabs boron, but need to move on to BL carbon.
And also work out profile variants, for different types headless and specific forms of graphical boxes, tablets and panels.

See doc/CB_CONF.md for more on included devices.
Some of the classes covered will include their own power charge, but that is not a criteria.
