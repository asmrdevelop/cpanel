package Cpanel::CustInfo::Get;

# cpanel - Cpanel/CustInfo/Get.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::CustInfo::Get - Fetch contact fields

=cut

use Cpanel::CustInfo::Model ();
use Cpanel::CustInfo::Util  ();

our $VERSION = '2.1';

=head2 get_all_possible_contact_fields()

Returns all contact fields that are possible for the current logged in user.

=cut

sub get_all_possible_contact_fields {
    my $is_virtual = Cpanel::CustInfo::Util::is_user_virtual( $Cpanel::appname, $Cpanel::user, $Cpanel::authuser );
    return Cpanel::CustInfo::Model::get_all_possible_contact_fields($is_virtual);
}

=head2 get_active_contact_fields()

Returns all contact fields that are active for the current logged in user.

=cut

sub get_active_contact_fields {
    my $is_virtual = Cpanel::CustInfo::Util::is_user_virtual( $Cpanel::appname, $Cpanel::user, $Cpanel::authuser );
    return Cpanel::CustInfo::Model::get_active_contact_fields($is_virtual);
}

1;
