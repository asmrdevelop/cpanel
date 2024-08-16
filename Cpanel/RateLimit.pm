package Cpanel::RateLimit;

# cpanel - Cpanel/RateLimit.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RateLimit

=head1 SYNOPSIS

    my $wait_time = Cpanel::RateLimit::get_wait(
        'Cpanel::WebCalls::Constants',
        \@last_run_times,   # RFC 3339 format, Zulu time
    );

=head1 DESCRIPTION

This module implements logic for rate-limiting, subject to specific
restrictions in the caller.

=cut

#----------------------------------------------------------------------

use Cpanel::Time::ISO ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $wait_secs = get_wait( $CONSTANTS_NS, \@LAST_RUN_TIMES )

Returns the number of seconds a caller must wait before being able
to access the relevant resource. (0 is returned if no wait is needed.)

$CONSTANTS_NS is a namespace that defines functions C<RATE_LIMIT_ALLOWANCE()>
and C<RATE_LIMIT_PERIOD()>. For example, if the “allowance” is 3 and the
“period” is 100, that means to allow up to 3 requests per 100 seconds.

@LAST_RUN_TIMES is an array of prior run times. Each time is in the subset
of L<RFC 3339|https://www.rfc-editor.org/rfc/rfc3339.html> returned by
L<Cpanel::Time::ISO>.

=cut

sub get_wait ( $consts_module, $last_run_times_ar ) {    ## no critic qw(ManyArgs) - mis-parse
    my $wait;

    if ( @$last_run_times_ar > $consts_module->RATE_LIMIT_ALLOWANCE() ) {

        # @$last_run_times_ar *SHOULD* normally be sorted, but let’s not
        # depend on that.
        if ( my $last_ran_at = ( sort @$last_run_times_ar )[0] ) {
            $last_ran_at = Cpanel::Time::ISO::iso2unix($last_ran_at);

            my $earliest_time = $last_ran_at + $consts_module->RATE_LIMIT_PERIOD();
            $wait = $earliest_time - _time();

            $wait = 0 if $wait <= 0;
        }
    }

    return $wait // 0;
}

# overridden in tests
sub _time {
    return time;
}

1;
