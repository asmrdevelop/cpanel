package Cpanel::ProcessLog::AbstractUPIDSuccessFail;

# cpanel - Cpanel/ProcessLog/AbstractUPIDSuccessFail.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ProcessLog::AbstractUPIDSuccessFail

=head1 SYNOPSIS

See L<Cpanel::ProcessLog>.

=head1 DESCRIPTION

This module provides an abstract implemention of the L<Cpanel::ProcessLog> framework
for a generic process log directory that includes the output and C<SUCCESS> metadata
indicating the state of the process.

=head1 METADATA

This class defines metadata as:

=over

=item * C<SUCCESS> - either 0 (failure) or 1 (success).

=back

=cut

use parent 'Cpanel::ProcessLog';

use Cpanel::Exception ();
use Cpanel::UPID      ();

use constant _METADATA_SCHEMA => (
    'SUCCESS',    #boolean
);

sub _new_log_id_and_metadata {
    return (
        Cpanel::UPID::get($$),
        SUCCESS => 0,
    );
}

sub _DIR($) {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

1;
