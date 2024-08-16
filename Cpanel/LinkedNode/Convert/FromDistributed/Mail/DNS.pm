package Cpanel::LinkedNode::Convert::FromDistributed::Mail::DNS;

# cpanel - Cpanel/LinkedNode/Convert/FromDistributed/Mail/DNS.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::FromDistributed::Mail::DNS

=head1 DESCRIPTION

This module implements DNS logic needed for de-distribution conversion
of accounts with distributed mail.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::Convert::Common::Mail::DNS ();
use Cpanel::LocaleString                           ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 do_zone_updates( %OPTS )

Wraps L<Cpanel::LinkedNode::Convert::Common::Mail::DNS>’s function
of the same name. The C<ipv6_msg> argument is not necessary, though.

=cut

sub do_zone_updates (%opts) {
    return _something_zone_updates( 'do_zone_updates', %opts );
}

=head2 plan_zone_updates( %OPTS )

Wraps L<Cpanel::LinkedNode::Convert::Common::Mail::DNS>’s function
of the same name. The C<ipv6_msg> argument is not necessary, though.

=cut

sub plan_zone_updates (%opts) {
    return _something_zone_updates( 'plan_zone_updates', %opts );
}

#----------------------------------------------------------------------

sub _something_zone_updates ( $action, %opts ) {
    my $ipv6_msg = Cpanel::LocaleString->new('The [asis,DNS] “[_1]” record for “[_2]” ([_3]) resolves to “[_4]”. The system needs to update this record to resolve to the local server, but the user “[_5]” does not control any [asis,IPv6] addresses on this server.');

    return Cpanel::LinkedNode::Convert::Common::Mail::DNS->can($action)->( %opts, 'ipv6_msg' => $ipv6_msg );
}

1;
