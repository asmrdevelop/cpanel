package Cpanel::OrDie;

# cpanel - Cpanel/OrDie.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module houses routines to "convert" non-excepted code returns to
# exceptions.
#----------------------------------------------------------------------

use strict;
use warnings;

use Try::Tiny;
use Cpanel::Context   ();
use Cpanel::Exception ();

#This assumes that:
#   - The first return value is a boolean indicator of success.
#   - The second return value contains a text description of the problem.
#
#This only returns what is *after* the status indicator. So, where you'd
#otherwise do:
#
#my ($ok, $payload) = _gives_two_part_return();
#
#...you can instead do:
#
#my $payload = multi_return( \&_gives_two_part_return );
#
#...which will indicate failure by throwing an exception. The exception
#is the same type as what Cpanel::Context::must_be_list() returns.
#
#NOTE: If the function returns more than two elements and this is not
#called in list context, we throw an exception:
#
#my $payload = multi_return( sub { return ( 1, 2, 3 ) } );  #DIES
#
#my ($payload1, $payload2) = multi_return( sub { return ( 1, 2, 3 ) } );  #OK
#
#my ($payload) = multi_return( sub { return ( 1, 2, 3 ) } );  #OK .. but why?
#
sub multi_return {
    my ($todo_cr) = @_;

    my ( $ok, @what_else ) = $todo_cr->();
    if ( !$ok ) {
        die Cpanel::Exception->create_raw( shift(@what_else), { extra_returns => \@what_else } );
    }

    if ( @what_else > 1 ) {
        no warnings 'uninitialized';    ## no critic qw(Warn)
        Cpanel::Context::must_not_be_scalar("Returned extra args: @what_else");
    }

    return wantarray ? @what_else : $what_else[0];
}

#NOTE: The passed-in function is called in LIST context.
#
sub convert_die_to_multi_return {
    my ($todo_cr) = @_;

    Cpanel::Context::must_be_list();

    my ( $ok, $err, @ret );
    try {
        @ret = $todo_cr->();
        $ok  = 1;
    }
    catch {
        $ok  = 0;
        $err = Cpanel::Exception::get_string($_);
    };

    return ( $ok, !$ok ? $err : @ret );
}

1;
