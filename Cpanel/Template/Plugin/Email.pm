
# cpanel - Cpanel/Template/Plugin/Email.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Template::Plugin::Email;

use strict;
use warnings;

use base 'Template::Plugin';

use Cpanel                     ();
use Cpanel::Email::Maildir     ();
use Cpanel::API                ();
use Cpanel::Validate::EmailRFC ();

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::Email

=head1 DESCRIPTION

Plugin that exposes various Email related methods to the Template Toolkit pages.

=head1 METHODS

=head2 C<get_user_default_email_quota()>

Gets the default email quota.

=head3 Returns

Returns the default email quota as a number or the string “unlimited”.

=cut

sub get_user_default_email_quota {

    my ( $cpdata, $cpconf ) = ( $Cpanel::CPDATA{'MAX_EMAILACCT_QUOTA'}, $Cpanel::CONF{'email_account_quota_userdefined_default_value'} );

    if ( $cpconf && ( !$cpdata || "$cpdata" eq "unlimited" ) ) {
        return $cpconf;
    }
    elsif ( $cpdata && "$cpdata" ne "unlimited" && ( !$cpconf || $cpconf eq "unlimited" ) ) {
        return $cpdata;
    }
    elsif ( $cpdata && $cpconf ) {
        return "$cpdata" ne "unlimited" && "$cpconf" ne "unlimited" && $cpdata < $cpconf ? $cpdata : $cpconf;
    }

    return Cpanel::Email::Maildir::get_default_email_quota_mib();
}

=head2 C<get_default_address()>

Gets the default email address for the main domain.

=head3 Returns

Returns the default email domain as a string.

=cut

sub get_default_address {
    if ( $Cpanel::appname eq 'webmail' ) {
        return "";
    }
    my $result         = Cpanel::API::execute( "Email", "list_default_address", { "domain" => $Cpanel::CPDATA{'DNS'} } );
    my $defaultaddress = $result->data()->[0]->{defaultaddress};
    my $is_email       = Cpanel::Validate::EmailRFC::is_valid($defaultaddress);

    if ( !$is_email ) {
        return "";
    }

    return $defaultaddress;
}

1;
