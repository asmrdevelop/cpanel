package Cpanel::Security::Authn::APITokens::Validate::whostmgr;

# cpanel - Cpanel/Security/Authn/APITokens/Validate/whostmgr.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::APITokens::Validate::whostmgr

=head1 SYNOPSIS

    my @parts = Cpanel::Security::Authn::APITokens::Validate::whostmgr->NON_NAME_TOKEN_PARTS();

    Cpanel::Security::Authn::APITokens::Validate::whostmgr->validate_creation(
        \%params,
    );

    Cpanel::Security::Authn::APITokens::Validate::whostmgr->validate_update(
        \%token_data_hr,
        \%params,
    );

=head1 WHM-SPECIFIC NOTES

WHM API Tokens optionally accept an array of C<acls>. This array
is not validated.

WHM API Tokens optionally accept an array of C<whitelist_ips>.

See L<Cpanel::Security::Authn::APITokens::Object::whostmgr> for more
information about this array and its significance.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Security::Authn::APITokens::Validate';

use constant _NON_NAME_TOKEN_PARTS => ('acls');

# TODO: Validate ACL names in WHM API tokens.
use constant _validate_service_parts => ();

use Cpanel::Exception ();

sub _err_no_update {
    return Cpanel::Exception->create('Specify a new name, updated [asis,ACL]s, or [asis,IP]s.');
}

1;
