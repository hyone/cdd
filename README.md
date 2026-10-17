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

Inside a Herdr pane, cdd is detected via `TERM_PROGRAM=herdr` /
`HERDR_ENV=1` and records the directory as

    herdr/<session>,<workspace>.<pane>      (for example herdr/main,1.2)

In the current session, these short forms work:

    cdd 1.2       workspace 1, pane 2
    cdd w1:p2     same, using the raw Herdr pane ID
    cdd p2        pane 2 in the current workspace
    cdd 1         workspace 1, pane 1 (the default pane)

tmux keys stay `session,window.pane` (for example `main,1.0`), so the same
`$CDD_FILE` can be shared by tmux and Herdr.

When tmux and Herdr are nested, the innermost multiplexer is detected via
`$TERM_PROGRAM`. Set `CDD_MULTIPLEXER` to `herdr`, `tmux`, `screen`, `none`
or `auto` (the default) to override the detection.

## Tests

    ./test/run.sh

## License

http://m4i.mit-license.org/2012
