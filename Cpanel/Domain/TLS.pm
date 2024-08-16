package Cpanel::Domain::TLS;

# cpanel - Cpanel/Domain/TLS.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Domain::TLS - Read the domain-level TLS datastore.

=head2 DESCRIPTION

    if ( Cpanel::Domain::TLS->has_tls('somedomain.tld') ) {
        my ($key, $crt, @cab) = Cpanel::Domain::TLS->get_tls('somedomain.tld');
        #...
    }

    my @domains = Cpanel::Domain::TLS->get_tls_domains();

    #For things that need to know where the file is on disk.
    my $path = Cpanel::Domain::TLS->get_tls_path('somedomain.tld');

    #Same, but for the certificates (exclusive of the key).
    my $cpath = Cpanel::Domain::TLS->get_certificates_path('somedomain.tld');

=head1 DISCUSSION

All cPanel users can use these read functions, though we limit some
items to the C<root> and C<mail> system users.

For write controls, look to L<Cpanel::Domain::TLS::Write>.

=cut

use Try::Tiny;

use Cpanel::Autodie        ();
use Cpanel::Context        ();
use Cpanel::Exception      ();
use Cpanel::FileUtils::Dir ();
use Cpanel::LoadFile       ();
use Cpanel::LoadModule     ();
use Cpanel::PEM            ();

use constant {
    _ENTRY_TYPE => 'FQDN',
};

our $BASE_PATH;

BEGIN {
    $BASE_PATH = '/var/cpanel/ssl/domain_tls';
}

=head1 METHODS

=head2 I<CLASS>->get_tls_path( FQDN )

This returns the path that contains the combined TLS resources in a single
file: the key then all certificates, starting with the “leaf” certificate.

=cut

sub get_tls_path {
    my ( $class, $fqdn ) = @_;

    #NB: FQDNs can be up to 253 bytes. A single filesystem node
    #can be up to 255 bytes. So we’re OK to store the FQDN on disk,
    #but we only have two more bytes to spare, so no “.pem” extension.
    #Rather than “live on the edge” with a “.p” extension (<snicker>),
    #let’s just use the FQDN itself.
    return $class->_get_entry_dir($fqdn) . '/combined';
}

=head2 I<CLASS>->get_certificates_path( FQDN )

This returns the path that contains the certificates in a single
file, starting with the “leaf” certificate.

=cut

sub get_certificates_path {
    my ( $class, $fqdn ) = @_;

    return $class->_get_entry_dir($fqdn) . '/certificates';
}

=head2 I<CLASS>->has_tls( FQDN )

Returns 1 or 0 to indicate whether the datastore contains an entry
for the given FQDN. This will consider a pending-delete entry not
to exist.

=cut

sub has_tls {
    my ( $class, $domain ) = @_;

    if ( !length $domain ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess( sprintf( "Need %s!", $class->_ENTRY_TYPE() ) );
    }

    if ( !Cpanel::Autodie::exists( $class->_get_pending_delete_path($domain) ) ) {
        my $path = $class->get_tls_path($domain);

        return 1 if Cpanel::Autodie::exists($path);
    }

    return 0;
}

=head2 @fqdns = I<CLASS>->get_tls_domains()

Returns every name entry in the datastore. This will exclude
any entries that are pending deletion.

=cut

sub get_tls_domains {
    my ($class) = @_;

    Cpanel::Context::must_be_list();

    #If the directory doesn’t exist, then there’s nothing installed.

    my $domains_ar = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists( $class->BASE_PATH() );

    return if !$domains_ar;

    $class->_filter_pending_deletions($domains_ar);

    return grep { substr( $_, 0, 1 ) ne '.' } @$domains_ar;
}

=head2 ( $key, @certs ) = I<CLASS>->get_tls( FQDN )

Returns the key and certificates for the given FQDN, in PEM format.
Certificates are ordered with the “leaf” node first.

This will return the contents of entries that are pending deletion.

If the given FQDN doesn’t have a key/certs, then this returns empty.
Don’t use this to determine existence, though,
unless you don’t need the pending-deletion check that C<has_tls()> does.

=cut

#Returns key, then leaf cert, then the cert chain
sub get_tls {
    my ( $class, $domain ) = @_;

    Cpanel::Context::must_be_list();

    return _load_pems_path( $class->get_tls_path($domain) );
}

=head2 @certs = I<CLASS>->get_certificates( FQDN )

Returns the certificates (in PEM format) for the given FQDN,
ordered with the “leaf” node first.

This will return the contents of entries that are pending deletion.

If the given FQDN doesn’t have certificates, then this returns empty.
Don’t use this to determine existence, though,
unless you don’t need the pending-deletion check that C<has_tls()> does.

=cut

sub get_certificates {
    my ( $class, $domain ) = @_;

    Cpanel::Context::must_be_list();

    return _load_pems_path( $class->get_certificates_path($domain) );
}

=head2 I<CLASS>->get_mtime_path()

Returns a path that can be C<stat()>ed to know when the datastore last
changed.

(It would be more ideal just to expose a C<get_mtime()> method, but the
use case for this logic expects a filesystem path.)

=cut

#Because certificate additions, replacements, and deletions all update
#the directory, it’s safe to use that as a metric for when the datastore
#was last updated.
sub get_mtime_path {
    my ($class) = @_;
    return $class->BASE_PATH();
}

=head2 I<CLASS>->BASE_PATH()

Returns the datastore’s base path. This is a bit of an implementation
detail, so please don’t call this except for logic that maintains the
datastore.

=cut

#Accessed publicly
sub BASE_PATH () { return $BASE_PATH }

#----------------------------------------------------------------------

sub _filter_pending_deletions {
    my ( $class, $domains_ar ) = @_;

    my $exclusions_ar = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists( $class->_pending_delete_dir() ) || [];

    if (@$exclusions_ar) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Set');
        @$domains_ar = Cpanel::Set::difference( $domains_ar, $exclusions_ar );
    }

    return;
}

# The below functions can be called 100000x for account removal
# so small optimizations matter here

sub _pending_delete_dir {
    return $_[0]->BASE_PATH() . '/.pending_delete';
}

sub _get_pending_delete_path {

    #my ( $class, $domain ) = @_;

    $_[0]->_verify_entry( $_[1] );

    return $_[0]->_pending_delete_dir() . '/' . $_[1];
}

sub _get_entry_dir {

    #my ( $class, $domain ) = @_;

    $_[0]->_verify_entry( $_[1] );

    return $_[0]->BASE_PATH() . '/' . $_[1];
}

sub _verify_entry {

    #my ( $_[0], $fqdn ) = @_;

    if ( !length $_[1] ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess( sprintf( "Need %s!", $_[0]->_ENTRY_TYPE() ) );
    }

    #A rudimentary check to prevent malicious traversal.
    if ( -1 != index( $_[1], '/' ) || 0 == index( $_[1], '.' ) ) {
        die Cpanel::Exception::create(
            'DomainNameNotRfcCompliant',
            [ given => $_[1] ],
        );
    }

    return;
}

#----------------------------------------------------------------------

sub _load_pems_path {
    my ($path) = @_;

    my $pem = Cpanel::LoadFile::load_if_exists($path);

    return if !defined $pem;

    #Split on newlines between two dashes, but don’t
    #split on the actual dashes.
    return Cpanel::PEM::split($pem);
}

1;
