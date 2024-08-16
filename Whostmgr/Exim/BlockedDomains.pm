package Whostmgr::Exim::BlockedDomains;

# cpanel - Whostmgr/Exim/BlockedDomains.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Exim::BlockedDomains - Functions to manage the domains blocked by Exim

=head1 SYNOPSIS

    use Whostmgr::Exim::BlockedDomains ();

    Whostmgr::Exim::BlockedDomains::modify_blocked_incoming_email_domains( "block", [ "domain.tld" ] );
    Whostmgr::Exim::BlockedDomains::modify_blocked_incoming_email_domains( "unblock", [ "domain.tld" ] );

    # Wildcards are supported
    Whostmgr::Exim::BlockedDomains::modify_blocked_incoming_email_domains( "block", [ "*.co.uk" ] );
    Whostmgr::Exim::BlockedDomains::modify_blocked_incoming_email_domains( "unblock", [ "*.co.uk" ] );

    my $domains_ar = Whostmgr::Exim::BlockedDomains::list_blocked_incoming_email_domains();

=head1 DESCRIPTION

This module provides functions for managing the domains that are blocked from sending mail to
this server by Exim.

=head1 FUNCTIONS

=cut

our $_BLOCKED_DOMAINS_FILE = '/etc/blocked_incoming_email_domains';

=head2 modify_blocked_incoming_email_domains( $action, $domains_ar )

Blocks or unblocks the specified domains from sending mail to the server.

=over

=item Input

=over

=item $action - STRING

The action to perform.

The action argument must be either “block” or “unblock” to indicate whether the
specified domain should be added to or removed from the list of blocked domains.

=item $domains_ar - STRING

An ARRAYREF of domains to perform the action for.

This value allows for a leading wildcard to support blocking subdomains of a domain such as
*.domain.tld or *.com to block entire TLDs.

=back

=item Output

=over

This function returns 1 if the database was updated, 0 if no changes were required,
undef on failure.

=back

=back

=cut

sub modify_blocked_incoming_email_domains ( $action, $domains_ar ) {

    if ( $action ne 'block' && $action ne 'unblock' ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', "The parameter “[_1]” must be [list_or_quoted,_2].", [ "action", [ "block", "unblock" ] ] );
    }

    require Cpanel::StringFunc::File;

    if ( $action eq 'block' ) {
        require Cpanel::Validate::Domain;

        my @invalid_domains = grep { !Cpanel::Validate::Domain::validwildcarddomain( $_, 1 ) } @$domains_ar;

        if (@invalid_domains) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'InvalidParameter', '[list_and_quoted,_1] [numerate,_2,is not a valid,are not valid] “[_3]” [numerate,_2,value,values].', [ \@invalid_domains, scalar @invalid_domains, 'domain' ] );
        }

        return Cpanel::StringFunc::File::addlinefile( $_BLOCKED_DOMAINS_FILE, $domains_ar );
    }
    else {
        if ( grep { tr<\r\n><> } @$domains_ar ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'Line-break characters are forbidden.' );
        }

        return Cpanel::StringFunc::File::remlinefile( $_BLOCKED_DOMAINS_FILE, $domains_ar, 'full' );
    }

}

=head2 list_blocked_incoming_email_domains

Lists the domains that are blocked from sending mail to the server

=over

=item Input

=over

None

=back

=item Output

=over

This function returns an ARRAYREF of the domains blocked by Exim.

=back

=back

=cut

sub list_blocked_incoming_email_domains {
    require Cpanel::LoadFile;
    return [ split( m{\n+}, Cpanel::LoadFile::load_if_exists($_BLOCKED_DOMAINS_FILE) // '' ) ];
}

1;
