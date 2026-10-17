Inspired by [original cdd](http://d.hatena.ne.jp/secondlife/20080218/1203303528).

cdd records the current directory per pane/window and lets you move to that
directory from another one.

tmux 1.2 or higher, GNU screen and Herdr 0.9 or higher are supported.

## Usage

    cdd [last]                    move to the last directory
    cdd <key>                     move to the <key> directory
    cdd add <key> [directory]     add the directory to $CDD_FILE
    cdd delete <key>              delete the directory from $CDD_FILE
    cdd help|--help|-h            print this help message

## Herdr

Inside a Herdr pane, cdd records the current directory per pane as

    herdr/<session>,<workspace>.<pane>      (for example herdr/sub,4.2)

using stable Herdr IDs.  Short position keys are resolved when cdd runs, so
they follow the current tab and pane layout:

    cdd 1.2        tab 1, pane 2 in the current workspace
    cdd 3.1.2      workspace 3, tab 1, pane 2 in the current session
    cdd sub,1.2    tab 1, pane 2 in the active workspace of session sub
    cdd sub,3.1.2  workspace 3, tab 1, pane 2 of session sub

Stable keys always refer to the same pane:

    cdd w4:p2      exact pane, as shown by `herdr pane list`
    cdd p2         pane number 2 in the current workspace

Herdr encodes numbers over 9 as `pA` (=10) in its IDs; cdd accepts both the
Herdr ID form and the plain number (`cdd wA:p2`, `cdd 2.1`, ...).

Find pane IDs with `herdr pane list`, `echo $HERDR_PANE_ID`, or the
`workspace / tab / pane_id` detail line of the Goto picker (default
`prefix+g`).

When tmux and Herdr are nested, the innermost multiplexer is detected via
`$TERM_PROGRAM`. Set `CDD_MULTIPLEXER` to `herdr`, `tmux`, `screen`, `none`
or `auto` (the default) to override the detection.

## Tests

    ./test/run.sh

## License

http://m4i.mit-license.org/2012
