package Cpanel::SSL::Auto::DynamicDNS;

# cpanel - Cpanel/SSL/Auto/DynamicDNS.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::DynamicDNS

=head1 DESCRIPTION

This module contains logic for AutoSSL to interact with dynamic DNS.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 save_and_enqueue_notification( $USERNAME, $DOMAIN, $KEY_PEM, $CERT_PEM )

Saves the given (PEM-formatted) key and certificate to the user’s
SSLStorage (cf. L<Cpanel::SSLStorage::User>) then
enqueues an C<AutoSSL::DynamicDNSNewCertificate> notification to be
sent.

=cut

sub save_and_enqueue_notification ( $username, $domain, $key_pem, $cert_pem ) {    ## no critic qw(ManyArgs) - mis-parse
    my $ok;

    require Cpanel::SSLStorage::User;
    my $sslstorage = Cpanel::SSLStorage::User->new( user => $username );

    ( $ok, my $records_hr ) = $sslstorage->add_key_and_certificate_if_needed(
        key  => $key_pem,
        cert => $cert_pem,
    );
    die "add key & cert to sslstorage: $records_hr" if !$ok;

    my $cert_hr = $records_hr->{'certificate_record'};

    require Cpanel::Notify::Deferred;
    Cpanel::Notify::Deferred::notify(
        (
            map { $_ => 'AutoSSL::DynamicDNSNewCertificate'; } qw(class application),
        ),
        constructor_args => [

            # copied from Cpanel/SSL/Auto/Provider.pm
            # XXX TODO: refactor/normalize
            user                              => $username,
            username                          => $username,
            to                                => $username,
            notification_targets_user_account => 1,

            domain         => $domain,
            certificate_id => $cert_hr->{'id'},
        ],
    );

    return;
}

1;
