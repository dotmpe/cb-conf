# 9front experimental desktop
Plan 9 is a distributed system, but the downloadable 9front disk is ready to run a single-host system called 'cirno', with user 'glenda'.
Normally the system CPU, storage, and other resources may be provided by dedicated hosts on different platforms.

Setting up the 9front QEMU desktop from CoW seed disk entails:

- Configure for a VESA monitor setup so that Rio starts
- Set other boot parameters `plan9.ini` for promptless startup
- Customize sysname in `/rc/bin/termrc.local` for custom host name
- Customize apps in `$home/bin/rc/riostart` for personal startup windows
- Customize UI font via `lib/profile` (only a few choices, but you do not need to use VGA fonts)
- Configure the IP address

The simplest to do the above is to either use a custom CD-ROM image to input the bootstrap scripts,
or start the network and download the script. The latter is the least script but
requires a python http.server running on the host's project folder. To do all
above setup steps:
```rc
term% ip/config
term% conf_url='http://10.0.2.2:8000/'
term% hget $conf_url/config/vm/guest/9front/1stboot.rc | rc
term% hget $conf_url/lib/git/config-user > lib/git/config
# Or via a tarbal package
# hget http://10.0.2.2:8000/bundle.tar | tar x
```

The desktop should now start, and provide one regular rc terminal window and one for an rc session that also appears at the console.
Output from scripts during bootstrap wil be drawn on the root pane.

With the `uc-vm.bash` commands instead of the above the custom CD-ROM ISO may used for the same, only but without HTTP networking if you like:
```rc
9660srv
mounted=()
for (d in /dev/sdD0/data /dev/sd*/data) {
  if (~ $#mounted 0) {
    if (mount /srv/9660 /n/cfg $d >[2]/dev/null) {
      if (test -f /n/cfg/startup.rc) { mounted=$d; echo $d }
      if not unmount /n/cfg
    }
  }
}
. /n/cfg/1stboot.rc
# If you include lib/git/config with the ISO
#cp /n/cfg/gitconfig-user $home/lib/git/config
. /n/cfg/startup.rc
```

The above is more of a sketch than a polished demo.
XXX: Also like vgasize it may be possible to paramterize your scripts through plan9.ini itself

Now make a Git clone and do some work:
```rc
term% cd $home/src/local
term% git/clone ssh://glenda@10.0.2.2/usr/git/local/cb-conf.git
term$ echo Work > newfile
term% git/add newfile
term% git/commit -m "Something something" .
term% git/push
```

The above assumes:

- Project work trees go into `src/local`, or `src/vendor/<domain>/<owner>` depending on wether they are primary or not.

- Bare repos can live under `$home/git`, besides the `lib/git` dir with user git config (see /sys/lib/git/config for global settings).

  Under `$home/git`: `local/<owner>` for a user's repo collection, or/and `vendor/<vendor>/<owner>` for everything else.

  But note: as namespaces can be build outside of the filetree there is no need to invent intermediate *symbolic* paths, like ~/project or ./local for things that are really in /src, /usr, /mnt, /srv or elsewhere.
  Ony unless you specifically want to, to make such group to insert as a layer through the binds for a certain process namespace.

  (But so `local/<owner>` may already be superfluous or redundant.)

Future improvements:

- TODO: test/demo plan9.ini for bootstrap param other than vgasize or standard
- TODO: Config (git/email/...) user other than glenda
- TODO: git guestrc demo params [see guest.rc bootstrap]
- TODO: email inbox demo idem
- TODO: menu for listing other demo scripts and command collections:

  - viewer for native and/or web images, documents, other media:
  - video (would be very limited/niche feature for plan 9: the OS is intentionally a non-ECMA design, and has a tiny community)
  - CAD/SVG/plot, look for diagrams (ie. dot), or simple graphics context API
  - GIS/maps
  - 3D/mesh

Also noted:

- Nothing in terms of modern web (CSS+JS) engines, either try NetSurf 9front
  port or use VNC to other systems. Or read from RSS feeds.

  Classic browsers are mothra, abaco (basic HTML or text+graphics, no CSS/JS),
  Charon (Inferno, ancient) or Links (port, buggy).

## 9front first boot
To boot the VM into the desktop (Rio) environment, the monitor has to be put in VESA mode in the boot config.
Then during init, a `aux/realemu` process must started before `rio` runs.

The boot prompt and user can be set in the boot parameters as well. To add/edit parameters, change the guest `plan9.ini` file. For example:
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
Use any VESA resolution/aspect, QEMU has `640x480`, `800x600` (all 4:3), and `1280x800` (19:10). To list type:
```rc
    @{rfork n; aux/realemu; aux/vga -m vesa -p}
```
Finally to get a destkop at least:
```rc
    @{rfork n; aux/realemu; aux/vga -l $vgasize}
```
That line should be before `rio -i riostart` in profile, so...
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
interactively with ed. And in other words, with the exact same Bourne shell syntax for literal heredocs:
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

If Rio is up now, you can skip to network and then git. Or read and experiment a bit more first.

## using the shell session
The terminal takes some getting used to, the line dicipline is different from Linux so a regular terminal on the console will not behave.

In Rio, cursor and page keys move the scroll position and not the cursor itself.
Only the left and right keys will move the cursor.
Also you can edit the *entire* buffer, and it will never repair so some unfamiliar personal dicipline is required.

Some shortcut keys are:

- Ctrl+a → move to start of line
- Ctrl+b → move to just after the prompt, ie. to reset reset the cursor
- Ctrl+e → move to end of line
- Ctrl+u → erase entire line
- Ctrl+w → erase last word
- Ctrl+h → backspace
- Ctrl+f → complete
- Del → interrupt, or to refresh the prompt

Note that only the erase also works in the console session.

There is no history built in, or available via some readline lib like in Linux.

There is no `less`, or `more`, or even `expr` or `type`. You have cat, head or tail, awk, grep, cut and many others you will know from Linux/BSD type shell but in a more unpolluted, design-pure state.
That instead includes `whatis`, `rfork` and `flag`.
Still the shell rc is very Bourne (and Bash-) like, and capable but only more rudimentary.
Just read `man rc` or `page /sys/doc/rc.pdf`.
Note that variable sequences and quoting are entirely different from Bash, there is no double-quotes `"` string notation here.

No find, use `walk`, or `du -a . | grep pattern`.

- `walk -f` → list all files recursively (like `find . -type f`)
- `walk -d` → directories only
- `walk -eUp | grep user` → by user
- `walk -emp | awk '$1>1000000'` → by size

When editing files remember to leave the last line-end/EOL or you will get problems like rc syntax errors on the last file line.

The most suprising is that functions are exported, and are rc typeset (the output format is valid rc input):
```
term% ls /env|grep fn
'/env/fn#sigexit'
'/env/fn#term%'
term% fn myfun {echo $*}
term% whatis myfun
fn myfun {
    echo $*
}
term% ls /env|grep myfun
'/env/fn#myfun'
term% cat /env/fn'#'myfun
fn myfun {
    echo $*
}
```

And also as expected: any form of string modification and slicing is strictly a program affair; rc only sequencences the commands and arguments.

## 9front desktop usage
Plan 9 is heavy on mouse chording for control.

Right-click (RMB) on the grey desktop/root pane opens the *interactive menu* for window functions.
This has open, modify, close and hide as well as a session exit.
Or text function if you combine with Shift.

Left- and right-mouse clicks can be similary used on window borders to resize or drag them.
As do other modifiers like control, so you will want to capture mouse with the QEMU guest window (ctrl+alt+g, to release repeat id.) and use some compatible or pass-through mode with your regular host desktop/WM keyboard bindings.

To find stacked or hidden windows, you use the root+right-click menu (the windows are listed at the bottom).

Editors are `ed` in the terminal, and `sam` or `acme` in Rio.
Acme editor is the center piece for Plan 9. To open files or run commands, middle mouse click (or shift+RMB) them. Panes can be rearranged.

Look in /bin/games (graphical demos, simple games like mines, and other related utils) to start with looking at some things first.
They start in a window by tying `window <command>`. 

- `clock` for an analog clock window
- or `bar` for a small "digital" time / text line window which sticks to the right-hand bottom corner
- `cal 2026` for a monospace preformatted calendar
- `stats` (normally already running, you'll find `bin/rc/riostart` runs it)
- `faces` e-mail client
- `mothra` and `abaco` for web
- `page` for PDF

Here is a slightly customized riostart example with scrolling windows and a custom console prompt:
```
cons% cat bin/rc/riostart
#!/bin/rc
window 0,0,161,117 stats -lmisce
window bar

window -miny 160 -dy 400 -dx 900 -scroll rc

# run a system shell on the serial console
~ $#console 0 || prompt=('cons% ' '  ') window -m -scroll -miny 200 -dx 800 console
```

## 9front desktop config
The workflow takes some getting use to.
In the terminal, any text can be edited. In acme as well.

`wloc` outputs the current windows, with geometry and command name.
