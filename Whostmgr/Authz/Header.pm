package Whostmgr::Authz::Header;

# cpanel - Whostmgr/Authz/Header.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use MIME::Base64      ();
use Cpanel::Exception ();

=head1 NAME

Whostmgr::Authz::Header

=head1 DESCRIPTION

A module to get the 'Authorization' HTTP header for WHM.

=head1 METHODS

=head2 get_authorization_header

=head3 Purpose

    Gets the 'Authorization' HTTP header for WHM.

=head3 Arguments

    whmuser         - The WHM username to use when connecting to WHM.
    whmpass         - An optional argument to use when connecting to WHM.
                      If this value is not present then accesshash_pass must be specified.
    accesshash_pass - An optional argument to use when connecting to WHM.
                      If this value is not present then whmpass must be specified.

=head3 Exceptions

    Cpanel::Exception::MissingParameter - Thrown if any of the required parameters (or neither of the optional ones) are supplied.

=head3 Returns

    The 'Authorization' HTTP header to use to connect to WHM.

=cut

sub get_authorization_header {
    my (%OPTS) = @_;

    if ( !length $OPTS{whmuser} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'whmuser' ] );
    }

    if ( !length $OPTS{accesshash_pass} && !length $OPTS{whmpass} ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must supply [numerate,_1,the following parameter,one of the following parameters]: [join,~, ,_2]', [ 2, [qw( whmpass accesshash_pass )] ] );
    }

    if ( length $OPTS{accesshash_pass} ) {
        return sprintf( 'WHM %s:%s', $OPTS{whmuser}, $OPTS{accesshash_pass} );
    }
    else {
        my $base64_authz_token = MIME::Base64::encode_base64( sprintf( '%s:%s', $OPTS{whmuser}, $OPTS{whmpass} ) );
        chomp($base64_authz_token);
        return 'Basic ' . $base64_authz_token;
    }
}

1;
