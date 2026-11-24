# Dotfile depository for (semi) thin-client setups

Profiles here will be for devices with RAM >= 2GB and fast, non-MMC/Flash data partitions and shares.

That includes some thin-clients, rooted chromebooks, and many more capable single board computers [SBC] and System-on-Chips [SoC].
Unlike full seats or workstations the host and environment depends more on other network shares and services.
This does not (entirely) depend on those like a true networked terminal or thin-client, and it can boot and run on its own in standalone mode(s).

Device classes with even fewer resources at <2GB RAM or diskless belong in sbc-conf,
another dotfiles repo but for platforms like routers or SoC that can hold some protocol/OS stacks
but need to work within constrained memory and/or diskless cq slow, read-only boot and root platforms.

## Profiles
XXX: both uc-vm.bash commands `cmd` and `run` reset the overlay, so either use them for single-use sessions, or keep that command output in new fresh script. See run-template.bash; should make a command as well

- [9front: experimental desktop](9FRONTDESK.md) purist file IPC centric OS
- TODO: [cb-headless](DEBHEADLESS.md) on a Debian 13 CoW copy
- XXX: [blboron-desktop](BLBORON.md) untested, old Debian 12/Bookworm + Xorg / OpenBox
- TODO: [blcarbon-desktop](BLCARBON.md) new Debian 13 desktop

###### Id: CB_CONF
