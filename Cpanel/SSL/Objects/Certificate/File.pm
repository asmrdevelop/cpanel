package Cpanel::SSL::Objects::Certificate::File;

# cpanel - Cpanel/SSL/Objects/Certificate/File.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use parent 'Cpanel::SSL::Objects::Certificate';

use Cpanel::Exception            ();
use Cpanel::AdminBin::Serializer ();    # for utf8 safety

=encoding utf-8

=head1 NAME

Cpanel::SSL::Objects::Certificate::File - Store and cache certificate objects on disk

=head1 SYNOPSIS

    use Cpanel::SSL::Objects::Certificate::File ();

    my $obj = Cpanel::SSL::Objects::Certificate::File->new( path => "$dir/cert.pem" );

=head1 DESCRIPTION

This module is used to access certificate files on disk that are stored
in PEM format.  The module will keep a cache of the certificate parse to
avoid the expensive certificate parsing that needs to be done to create
the Cpanel::SSL::Objects::Certificate object.

The cache is currently stored along side the certificate file as $file.cache

=cut

use constant {
    _ENOENT      => 2,
    CACHE_SUFFIX => '.cache',
    CACHE_MODE   => 0644        # the cache never has the key in it
};

sub new {
    my ( $class, @args ) = @_;

    return $class->_new( 'load', @args );
}

sub new_if_exists {
    my ( $class, @args ) = @_;

    return $class->_new( 'load_if_exists', @args );
}

sub _new {
    my ( $class, $load_func, %opts ) = @_;

    my $path = $opts{'path'};
    if ( !length $path ) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'path' ] );
    }

    my $mtime = ( stat($path) )[9] or do {
        if ( $! == _ENOENT() ) {
            return undef if $load_func eq 'load_if_exists';
            die Cpanel::Exception::create( 'IO::FileNotFound', [ path => $path ] );
        }

        die Cpanel::Exception::create( 'IO::StatError', [ path => $path, error => $! ] );
    };

    if ( open( my $cache_fh, '<', $path . CACHE_SUFFIX ) ) {
        my ( $cache_size, $cache_mtime ) = ( stat($cache_fh) )[ 7, 9 ];
        if ( $cache_size && $cache_mtime >= $mtime && $cache_mtime <= time() ) {
            my $cache_ref = Cpanel::AdminBin::Serializer::LoadFile($cache_fh);
            close($cache_fh);
            if ( $cache_ref && ref $cache_ref eq 'HASH' && $cache_ref->{'_VERSION'} eq $Cpanel::SSL::Objects::Certificate::VERSION ) {    # PPI NO PARSE - Cpanel::SSL::Objects::Certificate is this module's parent..
                return bless $cache_ref, $class;
            }
        }
    }
    elsif ( $! != _ENOENT ) {
        warn "open($path" . CACHE_SUFFIX . "): $!";
    }

    # no cache, we must build it
    require Cpanel::LoadFile;
    require File::Basename;
    require Cpanel::FileUtils::Write;
    require Cpanel::PEM;
    my $cert = Cpanel::LoadFile->can($load_func)->($path);

    #Account for new_if_exists().
    return undef if !defined $cert || !$cert;

    # We could use Cpanel::SSL::Utils::get_certificate_from_text here, but that would be slower
    my ( $leaf_pem, @untrusted ) = Cpanel::PEM::split($cert);

    # Combined files are stored with the key first, then the cert
    # NB: This works for ECC as well as RSA.
    if ( index( $leaf_pem, 'PRIVATE KEY' ) >= 0 ) {
        $leaf_pem = shift @untrusted;
    }

    my $obj = $class->SUPER::new( 'cert' => $leaf_pem );

    $obj->{'_extra_certs'} = \@untrusted;    # Must be added so its restored in the cache

    # write_class will rebless the object to $class
    $class->write_cache( $path, $obj );

    return $obj;
}

=head2 write_cache($path, $obj)

Write the cache that is used in Cpanel::SSL::Objects::Certificate::File
for a Cpanel::SSL::Objects::Certificate object to cache path for a given
file.

This is mostly useful to generate the cache if you have a
Cpanel::SSL::Objects::Certificate object.

Example:

my $cert_obj = Cpanel::SSL::Objects::Certificate->new(cert => $cert_pem);
Cpanel::SSL::Objects::Certificate::File->($path_to_where_cert_obj_will_be_saved, $cert_obj);

=cut

sub write_cache {
    my ( $class, $path, $obj ) = @_;

    # We must bless this in order to have JSON
    # use the TO_JSON sub in this module.
    bless $obj, $class;

    if ( ( stat( File::Basename::dirname($path) ) )[4] == $> ) {
        require Cpanel::FileUtils::Write;
        Cpanel::FileUtils::Write::overwrite( $path . CACHE_SUFFIX, Cpanel::AdminBin::Serializer::Dump($obj), CACHE_MODE );
    }

    return;
}

sub TO_JSON {
    my ($self) = @_;
    return { %{$self} };
}

1;
