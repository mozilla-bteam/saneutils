This is a set of tools to keep Dylan sane.


# Setup

Copy config.json.example to config.json

Replace the various `Bugzilla_logincookie` and `Bugzilla_login` with values from your browser's cookie list.
The easiest way of finding these is the 'Storage' tab of Firefox Dev-Tools

# Editing Milestones

The easiest way of running this is with docker and the examples below will showcase that.

It can also run locally, but note that perl 5.28
is required. `cpanm`, `carton`, or `cpm` can be used to install the dependencies.

Below is the command for editing the **Firefox** milestones on the **staging** server.

```bash
docker run --rm -ti -v "$(pwd)/config.json:/app/config.json" mozillabteam/saneutils \
    ./edit-milestones.pl --urlbase https://bugzilla-dev.allizom.org --product Firefox
```

This will spawn vim with a list of all milestones for **Firefox** loaded. If you prefer nano:
```bash
docker run --rm -ti -e EDITOR=nano -v "$(pwd)/config.json:/app/config.json" mozillabteam/saneutils \
    ./edit-milestones.pl --urlbase https://bugzilla-dev.allizom.org --product Firefox
```

The format for the milestones is:

```
id:0000    100 Milestone 10 [x]
```

Where `id:0000` is an identifier used to track changes to the milestone (such as renames),
`100` is the sort key (used for sorting the milestones in the UI) and `Milestone 10` is the milestone name.
The portion inside square braces (`[]`) is the active status. It can be either `[x]` for enabled or `[_]` for disabled.

The workflow here involves making changes using the text editor, saving the file,
and exiting. Any changes made to the file will be applied to the system passed to `--urlbase`,
so if a mistake is made simply quit the editor without saving.

Changes made to the sort key, name, and active checkbox will cause updates to the milestone.
Renames of milestones with no bugs are simple renames; renames of milestones *with* bugs will cause
bug updates to happen, so it is advisable to do this with a Bugzilla account that is a *silent user*.

Adding new milestones is done by adding new lines without the `id:XXXX` prefix, such as:

```
2710 Firefox 71 [x]
```

Note all three elements (sortkey, name, active checkbox) are required.

Finally, deleting lines will cause those milestones to be deleted -- but you cannot delete milestones that have bugs associated.

