package Cpanel::AcctUtils::Lookup;

# cpanel - Cpanel/AcctUtils/Lookup.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::AcctUtils::Lookup

=cut

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::AcctUtils::Account           ();
use Cpanel::AcctUtils::Lookup::Webmail   ();
use Cpanel::Exception                    ();

=head2 get_system_user()

Look up the cPanel account that owns a virtual account. This may be an
email, FTP, or web disk service account, or a subaccount. The ownership
is determined by who owns the domain.

=cut

sub get_system_user {
    my $sysuser = get_system_user_without_existence_validation( $_[0] );

    if ( !Cpanel::AcctUtils::Account::accountexists($sysuser) ) {
        die Cpanel::Exception::create( 'UserNotFound', [ name => $sysuser ] );
    }

    return $sysuser;
}

=head2 get_system_user_without_existence_validation()

The same as get_system_user, but will not throw an exception if the cPanel
account that owns the virtual account doesn't actually exist as a system user.

=cut

sub get_system_user_without_existence_validation {    ##no critic qw(RequireArgUnpacking)

    die Cpanel::Exception::create( 'UserNotFound', [ name => '' ] ) unless defined $_[0] && length $_[0];

    # No unpacking here because this needs to be fast
    if ( $_[0] =~ tr{/}{} ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid username because it contains a “[_2]” character.', [ $_[0], '/' ] );
    }

    return $_[0] if !Cpanel::AcctUtils::Lookup::Webmail::is_strict_webmail_user( $_[0] );

    # Handle webmail accounts and other virtual users
    my ($domain) = ( split( m{@}, $_[0], 2 ) )[1];

    my $sysuser = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'skiptruelookup' => 1, 'default' => '' } );
    if ( !length $sysuser ) {
        die Cpanel::Exception::create( 'DomainDoesNotExist', 'The domain “[_1]” does not exist.', [$domain] );
    }
    return $sysuser;
}
1;
