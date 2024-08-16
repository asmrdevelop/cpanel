package Cpanel::LinkedNode::Convert::Common::Mail::StateBase;

# cpanel - Cpanel/LinkedNode/Convert/Common/Mail/StateBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Common::Mail::StateBase

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

A base class for mail-conversion state objects. It extends
L<Cpanel::Hash::Strict>.

This probably should be subclassed once other workload conversions exist,
as it contains pieces that aren’t really germane to mail specifically.

=head1 SUBCLASS INTERFACE

All subclasses must define:

=over

=item * C<_source_server_claims_ip()> - Implementation of
C<source_server_claims_ip()> below.

=item * C<_source_server_claims_domain_p()> - Like
C<_source_server_claims_ip()> but for a domain.

=item * C<_origin_hostname()> - Returns the hostname of the
conversion’s origin server.

=back

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Hash::Strict';

use Cpanel::Imports;

use Promise::XS ();

use Cpanel::DNS::Unbound::Async ();
use Cpanel::Exception           ();

use constant _PROPERTIES => (
    'records_to_update',
    'old_local_manual_mx',
    'former_cpuser_mail_worker_cfg',
    'target_archive_deleted',
);

#----------------------------------------------------------------------

=head1 METHODS

This class defines a few convenience methods.

=head2 $yn = I<OBJ>->source_server_claims_ip( $IP_ADDRESS )

Returns a boolean that indicates whether the given $IP_ADDRESS
is one the source server claims as its own.

=cut

sub source_server_claims_ip ( $self, $ipaddr ) {
    return $self->_source_server_claims_ip($ipaddr);
}

=head2 promise($yn) = I<OBJ>->name_resolves_to_source_server_p( $NAME, $RECORD_NAME )

Returns a promise whose resolution is a boolean that indicates whether
$NAME resolves to the source server.

This logic is rather “presumptuous”; see the implementation for some
“outlier” conditions that trigger a truthy resolution to the returned
promise.

=cut

sub name_resolves_to_source_server_p ( $self, $name, $record_name_stripped ) {

    # If the name is the expected hostname, then no need to ask DNS.
    return Promise::XS::resolved(1) if $self->_origin_hostname() eq $name;

    return $self->_source_server_claims_domain_p($name)->then(
        sub ($has_owner_yn) {

            # If the name is managed by the source server, then also there’s no need to ask DNS.
            return 1 if $has_owner_yn;

            my $a    = $self->_get_unbound()->ask( $name, 'A' );
            my $aaaa = $self->_get_unbound()->ask( $name, 'AAAA' );

            # We could optimize this by resolving as soon as *either*
            # IPv4 or IPv6 indicate a match, but this simpler
            # logic is fine for now.
            return Promise::XS::all( $a, $aaaa )->then(
                sub (@result_ars) {
                    my $no_results = 1;

                    for my $result_ar (@result_ars) {
                        my $result = $result_ar->[0];

                        my $addrs_ar = $result->decoded_data();
                        return 1 if grep { $self->source_server_claims_ip($_) } @$addrs_ar;
                        $no_results &&= !@$addrs_ar;
                    }

                    if ($no_results) {
                        warn join(
                            q< >,
                            locale()->maketext( '[asis,DNS] does not contain any [asis,IP] addresses for “[_1]”.', $name ),
                            _probably_reloading(),
                            _will_update($record_name_stripped),
                        );

                        return 1;
                    }

                    # The only condition in which we consider a name *not* to
                    # resolve to the source is if the source doesn’t control
                    # the name, the name isn’t the local hostname, we got at
                    # least 1 IP address, and none of those IP addresses is
                    # local.
                    #
                    return 0;
                },

                sub ($why) {
                    my $errstr = Cpanel::Exception::get_string($why);

                    warn join(
                        q< >,
                        locale()->maketext( 'The system failed to determine if “[_1]” resolves to the origin server: [_2]', $name, $errstr ),
                        _probably_reloading(),
                        _will_update($record_name_stripped),
                    );

                    return 1;
                },
            );

        }
    );
}

#----------------------------------------------------------------------

sub _get_unbound ($self) {
    return $self->{'_unbound'} ||= Cpanel::DNS::Unbound::Async->new();
}

sub _probably_reloading () {
    return locale()->maketext('This is probably because your [asis,DNS] server has not finished reloading.');
}

sub _will_update ($name) {
    return locale()->maketext( 'The system will update the “[_1]” [asis,MX] record.', $name );
}

1;
