fc.manage
=========

fc.manage is our wrapper around nixos-rebuild. It is intended to be run both
from a systemd timer and manually from a root shell.

fc.manage does not only run nixos-rebuild, but performs additional regular
maintenance tasks so this is a one-stop solution for FC VMs.


fc-manage usage
---------------

The main modes of operation are as follows:

fc-manage --channel (-c)
    Download the latest FC nixpkgs from our Hydra and update the system. This is
    what the systemd timer usually does.

fc-manage --build (-b)
    Update the system, but don't pull channel updates from Hydra.

fc-manage --directory (-e)
    Updates various ENC dumps in `/etc/nixos` from the directory.


Invoke :command:`fc-manage --help` for a full list of options.


Automatic mode
--------------

When "--automatic" is passed in addition to "--channel" or
"--channel-with-maintenance", the channel update is run only every I minutes,
where I is defined with the "--interval" option (default: 120 minutes). A
persistent offset is generated randomly and saved to the timestamp file at
`/var/lib/fc-manage/fc-manage.stamp`.

Interval and offset together define points on the time axis which allow for one
channel update run::

  ------+------+------+------>
          ^  ^   ^
          |  |   `will do channel updates when invoked here
          |  `won't do channel updates when invoked here
          `mtime of the stamp file

This way, fc-manage can run channel updates with a definied minimum interval
independent of when it is triggered (be it by systemd or manually).


Flying Circus integration
-------------------------

The most important NixOS options in `/etc/nixos/local.nix` that control the
fc.manage timers are:

flyingcircus.agent.with-maintenance
    Build channel updates when they arrive, but defer activation to a scheduled
    maintenance window. Maintenance is scheduled automatically.

flyingcircus.agent.steps
    Controls the configuration steps which are run each time the timer triggers.
    See :command:`fc-manage --help` for available options.

flyingcircus.agent.enable
    Turn off the fc-manage systemd timer. Should only be needed in rare circumstances.


fc-resize usage
---------------

fc-resize checks the root volume size, the memory size and the number of virtual
cores against what ENC data say. The root volume can be transparently increased,
but for changing RAM size or the number of cores a reboot is scheduled.

It should hardly be necessary to call fc-resize from an interactive session.


Hacking
-------

Create a virtualenv::

    pyvenv-3.4 .
    bin/pip install -e ../fcutil
    bin/pip install -e ../fcmaintenance
    bin/pip install -e .\[test]

Run tests::

    bin/py.test

Alternatively, build the Nix expression::

    nix-build -I nixpkgs=path/to/nixpkgs shell.nix
