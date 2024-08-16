package Cpanel::CaptureFH;

# cpanel - Cpanel/CaptureFH.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie ();
use Cpanel::Finally ();
use Cpanel::Logger  ();

#This is here because some things (e.g., Cpanel::Logger) will write
#directly to STDERR or STDOUT, which produces emails from crontab when
#called from crontab. We don’t want to suppress the emails entirely,
#though, in case Perl itself fails to run. So, we want to redirect STDOUT
#and STDERR to the main error log for this function.
sub do_with_output_captured_to_path_if_non_tty {
    my ( $path, $todo_cr ) = @_;

    my $is_terminal = _stdin_is_terminal();

    #local() didn’t seem to work all that well here,
    #so try this instead.
    _open_or_warn( my $old_stdout, '>&', \*STDOUT );
    _open_or_warn( my $old_stderr, '>&', \*STDERR );

    my $put_back = Cpanel::Finally->new(
        sub {
            _open_or_warn( \*STDOUT, '>&=', $old_stdout );
            _open_or_warn( \*STDERR, '>&=', $old_stderr );
        }
    );

    if ( !$is_terminal ) {

        #This was originally done by opening a single filehandle
        #and then setting STDERR and STDOUT to that handle via open(>>&=)
        #or just assigning the typeglob; however, this produced problems
        #with IPC::Open3 (e.g., Cpanel::OpenSSL). Opening separate filehandles
        #seems more reliable.
        for ( \*STDERR, \*STDOUT ) {
            _open_or_warn( $_, '>>', $path );
            $_->autoflush(1);
        }
    }

    return $todo_cr->();
}

sub _open_or_warn {

    #Can’t use Try::Tiny because it’ll impose its own @_,
    #and taking references like \$_[0] can break things weirdly.
    local $@;
    if ( !eval { Cpanel::Autodie::open(@_); 1 } ) {

        #When we are root and not running from a TTY,
        #this will append to the log file.
        #Otherwise, it spits to STDERR.
        Cpanel::Logger->new()->warn("$@");
    }

    return;
}

#mocked in tests
sub _stdin_is_terminal { return -t \*STDIN }

1;
