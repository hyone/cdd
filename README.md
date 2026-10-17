Inspired by [original cdd](http://d.hatena.ne.jp/secondlife/20080218/1203303528).

cdd records the current directory per pane/window and lets you move to that
directory from another one.

tmux 1.2 or higher, GNU screen and Herdr 0.9 or higher are supported.

## Usage

    cdd [last]                    move to the last directory
    cdd <key>                     move to the <key> directory
    cdd list                      list the registered directories
    cdd add <key> [directory]     add the directory to $CDD_FILE
    cdd delete <key>              delete the directory from $CDD_FILE
    cdd help|--help|-h            print this help message

## Herdr

Inside a Herdr pane, cdd records the current directory per pane as

    herdr/<session>,<workspace-id>.<pane-id>      (for example herdr/sub,w4.p2)

using the Herdr IDs as they are.  Short position keys are resolved when cdd
runs, so they follow the current tab and pane layout:

    cdd 1.2        tab 1, pane 2 in the current workspace
    cdd 3.1.2      workspace 3, tab 1, pane 2 in the current session
    cdd sub,1.2    tab 1, pane 2 in the active workspace of session sub
    cdd sub,3.1.2  workspace 3, tab 1, pane 2 of session sub

Stable keys always refer to the same pane:

    cdd w4:p2      exact pane, as shown by `herdr pane list`
    cdd p2         the same pane id in the current workspace

Herdr IDs use base32 for numbers over 9 (`pA` = 10).  cdd stores them as-is,
so stored keys never look like the numeric position keys; `cdd w4:p2` and
`cdd p2` refer to them directly.

`cdd list` (and `cdd help`) shows each entry with its position key and stable
pane ID, for example `sub,1 (w4:p4): ~/work/cdd`.  The session name is always
shown, including the current session, and `last` is listed at the end.  When a
session has more than one workspace, entries use the explicit
`<session>,<workspace>.<tab>.<pane>` form (`sub,2.1.1 (w5:p1)`) so the
workspace position is always visible.  Entries of a session that is not
running are shown in the stored `herdr/<session>,...` form.

Find pane IDs with `herdr pane list`, `echo $HERDR_PANE_ID`, or the
`workspace / tab / pane_id` detail line of the Goto picker (default
`prefix+g`).

While running inside Herdr, a session-qualified numeric key such as
`sub,1` is resolved as a Herdr position key first.  To reach a tmux entry
with the same shape from a Herdr pane, use the exact stored key (for
example `sub,1.0`).

When tmux and Herdr are nested, the innermost multiplexer is detected via
`$TERM_PROGRAM`. Set `CDD_MULTIPLEXER` to `herdr`, `tmux`, `screen`, `none`
or `auto` (the default) to override the detection.

## Tests

    ./test/run.sh

## License

http://m4i.mit-license.org/2012
