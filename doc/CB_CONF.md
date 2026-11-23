# Dotfile depository for (semi) thin-client setups

Profiles here will be for devices with RAM >= 2GB and fast, non-MMC/Flash data partitions and shares.

That includes some thin-clients, rooted chromebooks, and many more capable single board computers [SBC] and System-on-Chips [SoC].
Unlike full seats or workstations the host and environment depends more on other network shares and services.
This does not (entirely) depend on those like a true networked terminal or thin-client, and it can boot and run on its own in standalone mode(s).

Device classes with even fewer resources at <2GB RAM or diskless belong in sbc-conf,
another dotfiles repo but for platforms like routers or SoC that can hold some protocol/OS stacks
but need to work within constrained memory and/or diskless cq slow, read-only boot and root platforms.

## Profiles

### 9front experimental desktop

Plan 9 is a distributed system, but the downloadable 9front disk is ready to run a single-host system called 'cirno', with user 'glenda'.
Normally the system CPU, storage, and other resources may be provided by dedicated hosts on different platforms.

These are the additional steps, to go from a downloaded QoW disk to a running, online and customized 9front.

- Fix the monitor setup so Rio starts
- Customize `$home/bin/rc/riostart` for personal startup app windows
- Customize sysname, by creating `/rc/bin/termrc.local`
- Customize UI font via `lib/profile`

- TODO: Configure network
- Make a Git clone and do some work

#### 9front first boot
To boot the VM into the desktop (Rio) environment, the monitor has to be put in VESA mode in the boot config.
Then during init, a `aux/realemu` process must started before `rio` runs.

The boot prompt and user can be set in the boot parameters as well. To add/edit parameters, change the guest `plan9.ini` file. For example from rc:
```rc
    term% 9fs 9fat
    term% cat /n/9fat/plan9.ini
    bootfile=9pc64
    console=0
    term% cat <<'EOF' >>/n/9fat/plan9.ini
    nobootprompt=local!/dev/sdC0/fs
    user=glenda
    monitor=vesa
    vgasize=1024x768x32
    EOF
    term% fshalt -r
```
Use any VESA resolution/aspect, QEMU has `640x480`, `800x600` (all 4:3), and `1280x800` (19:10). To list those, type:
```rc
    @{rfork n; aux/realemu; aux/vga -m vesa -p}
```
Finally to get a destkop at least:
```rc
    @{rfork n; aux/realemu; aux/vga -l $vgasize}
```
This line should be before `rio -i riostart` in profile, so...
```rc
    term% grep -n rio lib/profile
    16: 	rio -i riostart
    term% ed lib/profile
    746
    16i
    @{rfork n; aux/realemu; aux/vga -l $vgasize}
    .
    w
    791
    q
    term%
```
interactively. Or in other words, and with the exact same Bourne shell syntax for literal heredocs:
```rc
ed $home/lib/profile <<'EOF'
16i
@{ rfork n; aux/realemu; aux/vga -l $vgasize }
.
w
q
EOF
```

To reboot you can type `reboot`, but for a proper shutdown use `fshalt -r` or you'll lose work.

If Rio is up now, you can skip to network and then git. Or experiment a bit more first.

#### using the shell session
The terminal takes some getting used to, the line dicipline is different from Linux so a regular terminal on the console will not behave entirely correctly.

In Rio, cursor and page keys move the scroll position and not the cursor itself.
Only left and right move the cursor. And you can edit the *entire* buffer,
but it will never repair so some unfamiliar personal dicipline is required.

Some shortcut keys are:

- Ctrl+a → move to start of line
- Ctrl+b → move to just after the prompt, ie. to reset reset the cursor
- Ctrl+e → move to end of line
- Ctrl+u → erase entire line
- Ctrl+w → erase last word
- Ctrl+h → backspace
- Ctrl+f → complete
- Del → interrupt, or to refresh the prompt

Note that only the erase also works in the console (window).

There is no history built in, or available via some readline lib like in Linux (but there is a history command).

There is no `less`, or `more`. There is cat, head or tail, awk, grep and many others you will know from Linux/BSD type shell already.

No find, use `walk`, or `du -a . | grep pattern`.

- `walk -f` → list all files recursively (like `find . -type f`)
- `walk -d` → directories only
- `walk -eUp | grep user` → by user
- `walk -emp | awk '$1>1000000'` → by size

When editing files remember to leave the last line-end/EOL or you will get
problems like rc syntax errors on the last file line.

#### 9front desktop usage
Plan 9 is heavy on mouse chording for control.

Right-click (RMB) on the grey desktop/root pane opens the *interactive menu* for window functions.
This has open, modify, close and hide as well as a session exit.
Left- and right-mouse clicks can be similary used on window borders to resize or drag them.
As do other modifiers like control, so you will want to capture mouse with the QEMU guest window (ctrl+alt+g, to release repeat id.) and use some compatible or pass-through mode with your regular host desktop/WM keyboard bindings.

To find stacked or hidden windows, you use the root+right-click menu (they are listed at the bottom).

Editors are `ed` in the terminal, and `sam` or `acme` in Rio.

Acme editor is the center piece for Plan 9. To open files or run commands, middle mouse click (or shift+RMB) them. Panes can be rearranged.

Look in /bin/games (graphical demos, simple games like mines, and other related utils) to start with looking at some things first.
They start in a window by tying `window <command>`.

- `clock`
- `cal 2026` monospace preformatted calendar
- `stats` is normally already running, you'll find `bin/rc/riostart` runs that.
- `faces` e-mail client
- `mothra` web

Here is a slightly customized riostart:
```
cons% cat bin/rc/riostart
#!/bin/rc
window 0,0,161,117 stats -lmisce
window bar

window -miny 160 -dy 400 -dx 900 -scroll rc

# run a system shell on the serial console
~ $#console 0 || prompt=('cons% ' '  ') window -m -scroll -miny 200 -dx 800 console
```

#### 9front desktop config
The workflow takes some getting use to.
In the terminal, any text can be edited. In acme as well, and 

`wloc` outputs the current windows, with geometry and command name.


######
