package Cpanel::Terminal;

# cpanel - Cpanel/Terminal.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#NOTE: Can’t use anything here that requires external code.

my $INFOCMP_BIN = '/usr/bin/infocmp';

#NOTE: Different versions of CentOS have different max_colors values
#for the same terminal; for example, C6 gives 8 colors for “nsterm”,
#but C7 gives 256 colors. So, best to err on the side of caution and
#run infocmp.
#
my @KNOWN_TERMINAL_MAX_COLORS = (
    'xterm'          => 8,
    'putty'          => 8,
    'xterm-color'    => 8,
    'xterm-16color'  => 16,
    'xterm-256color' => 256,

    #This terminal actually supports 24-bit color;
    #however, terminfo doesn’t know how to represent that.
    #Unfortunately for us, the xterm people chose to omit
    #a max_colors indication from the terminfo entry entirely,
    #which is indistinguishable from a no-color terminal.
    #
    #We should be ok just adding such terminals to this list
    #as they are created.
    #
    'xterm-24' => 256,
);

my %cached_max_colors = (@KNOWN_TERMINAL_MAX_COLORS);

#exposed for testing
our $_cached_stdin_is_tty;
our $_cached_EXECUTABLE_NAME_is_cpanel_perl;
our $_disable_init_once;    # allow testing to disable the behavior

sub _init_once {
    $_cached_stdin_is_tty                   = undef;
    $_cached_EXECUTABLE_NAME_is_cpanel_perl = undef;

    #On the outside chance that we ever somehow use this module in a BEGIN block,
    #we’ll need to reset these variables.
    if ( !$_disable_init_once && ${^GLOBAL_PHASE} && ${^GLOBAL_PHASE} ne 'START' ) {
        no warnings 'redefine';
        *_init_once = sub { };
    }

    return;
}

sub it_is_safe_to_colorize {

    _init_once();

    if ( !defined $_cached_stdin_is_tty ) {
        $_cached_stdin_is_tty = -t STDIN;
    }

    if ($_cached_stdin_is_tty) {
        if ( !defined $_cached_EXECUTABLE_NAME_is_cpanel_perl ) {
            $_cached_EXECUTABLE_NAME_is_cpanel_perl = ( $^X =~ m{^/usr/local/cpanel/3rdparty/perl} );
        }

        return 1 if $_cached_EXECUTABLE_NAME_is_cpanel_perl;
    }

    return 0;
}

sub _run_infocmp_to_get_max_colors {
    my ($term) = @_;

    require Cpanel::SafeRun::Object;
    my $run = Cpanel::SafeRun::Object->new(
        'user'    => -1,
        'program' => $INFOCMP_BIN,
        'args'    => [ '-L', '-1', $term ],
    );

    if ( $run->stdout() =~ m{max_colors\#(\d+)} ) {
        return $1;
    }

    #We don't actually care if we got errors, that just means you get no colors

    return undef;
}

=head1 METHODS

=head2 get_max_colors_for_terminal($TERM)

INPUT:
    TERM  - pretty much the $TERM env var

OUTPUT:
    undef when num. colors cannot be determined; callers should probably coerce this to 0.
    Otherwise, returns the max # of colors supported by the passed TERM.

=cut

sub get_max_colors_for_terminal {
    my ($term) = @_;

    return undef if !length $term;

    if ( exists $cached_max_colors{$term} ) {
        return $cached_max_colors{$term};
    }

    my $max_colors = _run_infocmp_to_get_max_colors($term);

    if ( !length $max_colors ) {

        #e.g., rxvt-unicode-256color
        if ( $term =~ m{([0-9]+)color} ) {
            $max_colors = $1;
        }

        #NOTE: If we get here, assume the terminal is colorless.
        #That may not be a safe assumption in terminals that support
        #24-bit color but represent this in terminfo by not giving
        #a max_colors entry. (Grr...)
    }

    $cached_max_colors{$term} = $max_colors;

    return $max_colors;
}

1;
