package Cpanel::Streamer::Admin;

# cpanel - Cpanel/Streamer/Admin.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Streamer::Admin - Streamer for admin functions

=head1 DESCRIPTION

This module subclasses L<Cpanel::Streamer::ReportUtilUser>. It calls a given
streaming admin function and connects the stream
input & output to the function’s stream filehandle.

=head1 PARAMETERS

This module accepts a list of key/value pairs, thus:

=over

=item * C<admin_args> - REQUIRED. Arguments to give to
C<Cpanel::AdminBin::Call::stream()> (after the filehandle).
For example, the first argument here is the admin module namespace
(i.e., C<Cpanel> for cPanel-provided modules).

=item * C<get_exit_code_for_error> - OPTIONAL. A callback that receives
whatever error C<Cpanel::AdminBin::Call::stream()> might have thrown.
Its return value, if defined, will be the process’s exit value.
This is useful, e.g., to have the process exit with a specific code that
a caller can recognize programmatically.

=back

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Streamer::Base::ReportUtilUser';

use Cpanel::Streamer::ReportUtil ();
use Cpanel::AdminBin::Call       ();

use Socket ();

sub _init {
    my ( $self, %opts ) = @_;

    Cpanel::Streamer::ReportUtil::start_reporter_child(
        streamer => $self,
        todo_cr  => sub ($child_s) {
            Cpanel::AdminBin::Call::stream( $child_s, @{ $opts{'admin_args'} } );
        },
        %opts{'get_exit_code_for_error'},
    );

    return;
}

1;
