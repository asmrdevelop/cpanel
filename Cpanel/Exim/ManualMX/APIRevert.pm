package Cpanel::Exim::ManualMX::APIRevert;

# cpanel - Cpanel/Exim/ManualMX/APIRevert.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exim::ManualMX::APIRevert

=head1 SYNOPSIS

    my $promise = Cpanel::Exim::ManualMX::APIRevert::undo_p(
        $async_api_obj,
        {
            'domain.tld' => 'the.mail.server',
            'domain2.tld' => undef,
        },
    );

=head1 DESCRIPTION

This module contains logic to undo a prior set or unset API operation
for manual MX.

=cut

#----------------------------------------------------------------------

use Promise::XS ();

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @steps = undo_p( $ASYNC_API, \%OLD_STATE )

Starts an attempt to restore %OLD_STATE on the remote.

$ASYNC_API is a L<Cpanel::Async::RemoteAPI::WHM> instance, and
%OLD_STATE is the C<payload> from APIs like WHM API v1’s
C<set_manual_mx_redirects()>.

Returns a promise that resolves when that attempt completes.
This promise always resolves; failures are trapped and C<warn()>ed.

=cut

sub undo_p ( $api_obj, $old_state_hr ) {
    my ( %unset_args, %set_args );

    # Sort so what we do here is deterministic. (Eases testing.)
    for my $domain ( sort keys %$old_state_hr ) {
        my $old_host = $old_state_hr->{$domain};

        if ($old_host) {
            push @{ $set_args{'domain'} },  $domain;
            push @{ $set_args{'mx_host'} }, $old_host;
        }
        else {
            push @{ $unset_args{'domain'} }, $domain;
        }
    }

    my @p;

    if (%unset_args) {
        push @p, $api_obj->request_whmapi1( unset_manual_mx_redirects => \%unset_args );
    }

    if (%set_args) {
        push @p, $api_obj->request_whmapi1( set_manual_mx_redirects => \%set_args );
    }

    # Warn on failures.
    $_ = $_->catch( \&_warn_err ) for @p;

    # Ensure that we don’t return multiple things
    # since Cpanel::PromiseUtils dislikes multi-resolution.
    return Promise::XS::all(@p)->then( sub { } );
}

sub _warn_err ($err) {
    return warn Cpanel::Exception::get_string($err);
}

1;
