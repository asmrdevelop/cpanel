package Cpanel::APITimezone;

# cpanel - Cpanel/APITimezone.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::APITimezone

=head1 SYNOPSIS

    package Cpanel::API::MyModule;

    sub my_api_call ($args, $result, @) {

        local $ENV{'TZ'} = Cpanel::APITimezone::get_uapi_timezone($args);

        ..
    }

=head1 DESCRIPTION

This module normalizes logic to fetch a timezone for use in UAPI calls.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $tz = get_uapi_timezone( $ARGS )

Accepts a L<Cpanel::Args> instance. Returns the first of, in order of
preference:

=over

=item * The C<timezone> parameter from $ARGS.

=item * C<TZ> in the environment.

=item * The server’s calculated timezone as given from
C<Cpanel::Timezones::calculate_TZ_env()>.

=back

=cut

sub get_uapi_timezone ($args) {
    return $args->get('timezone') || $ENV{'TZ'} || do {
        require Cpanel::Timezones;
        Cpanel::Timezones::calculate_TZ_env();
    };
}

1;
