package Cpanel::Crypt::GPG::VendorKeys::Verify;

# cpanel - Cpanel/Crypt/GPG/VendorKeys/Verify.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 NAME

Cpanel::Crypt::GPG::VendorKeys::Verify -- Verification for vendor PGP/GPG keys.

=head1 SYNOPSIS

 use Cpanel::Crypt::GPG::VendorKeys::Verify ();

 my ($verify, $msg) = Cpanel::Crypt::GPG::VendorKeys::Verify->new(
     vendor => "cpanel",
     categories => ["test", "release"]
 );

 if (!$verify) {
     print "Failed to create Verify object: $msg\n";
 }

 my $is_valid = $verify->files(
     sig   => "test.files.asc",
     files => [ "test.file", "test.file.2" ],
 );

=head1 METHODS

=cut

use strict;
## no critic(RequireUseWarnings) -- This is older code and has not been tested for warnings safety yet.

use Cpanel::Crypt::GPG::Import::Temp               ();
use Cpanel::Crypt::GPG::VendorKeys                 ();
use Cpanel::Crypt::GPG::VendorKeys::TimestampCache ();

=pod

B<new( %args )> (constructor)

Create a new instance of this class.

I<%args> can contain:

=over 4

=item * vendor

Name of vendor used for verification.

=back

Returns a new instance of this class.
Returns undef on failure.

=cut

sub new {
    my ( $class, %args ) = @_;

    if ( !$args{vendor} ) {
        return _result( undef, "Argument 'vendor' is required." );
    }

    if ( !( $args{category} || $args{categories} ) ) {
        return _result( undef, "Argument 'category' or 'categories' is required." );
    }

    if ( $args{category} && $args{categories} ) {
        return _result( undef, "Both argument 'category' and 'categories' can not be used simultaneously." );
    }

    my $argcat = $args{category} || $args{categories};
    my $keys   = Cpanel::Crypt::GPG::VendorKeys::get_keys( vendor => $args{vendor}, category => $argcat );

    if ( !keys %{$keys} ) {
        return _result( undef, "No keys found for vendor '" . $args{vendor} . "'" );
    }

    my ( $pgp, $msg ) = Cpanel::Crypt::GPG::Import::Temp->new();

    if ( !$pgp ) {
        return _result( undef, $msg );
    }

    for my $key_id ( keys %{$keys} ) {
        my ( $success, $msg ) = $pgp->add_pub_key( key => $keys->{$key_id} );

        if ( !$success ) {
            return _result( undef, "Failed to add key '$key_id' : " . $msg );
        }
    }

    my $obj = {
        vendor     => $args{vendor},
        categories => ( ref($argcat) eq 'ARRAY' ) ? $argcat : [$argcat],
        keys       => $keys,
        pgp        => $pgp,
    };

    bless $obj, $class;

    return _result( $obj, "Success" );
}

=pod

B<files( %args )>

Verify a detached signature against files.

I<%args> can contain:

=over 4

=item * sig

Path to signature.

=item * files

Path to files.
Can be a scalar value for a singular file. Or an array reference for multiple.

=back

In scalar context, on successful validation, returns the UID of key, false value otherwise.
In list context returns a list containing ($success, $error_message).

=cut

sub files {
    my ( $self, %args ) = @_;

    if ( !( $args{sig} || $args{sig_data} ) ) {
        return _result( undef, "Arguments 'sig' or 'sig_data' must be provided." );
    }

    # It is possible for 'files_data' to be defined but 0 bytes.

    if ( !( $args{files} || defined( $args{files_data} ) ) ) {
        return _result( undef, "Arguments 'files' or 'files_data' must be provided." );
    }

    my ( $s, $m ) = $self->{pgp}->verify(%args);

    if ( !$s ) {
        return _result( $s, $m );
    }

    ( $s, $m ) = _check_filename( $s, $m, \%args );

    if ( !$s ) {
        return _result( $s, $m );
    }

    ( $s, $m ) = _check_rollback( $s, $m, \%args );

    if ( !$s ) {
        return _result( $s, $m );
    }

    $m = "Successfully verified signature for " . $self->{vendor} . " (key types: " . join( ", ", @{ $self->{categories} } ) . ").";
    return _result( $s, $m );
}

sub _check_rollback {
    my ( $sig_data, $message, $args ) = @_;

    my $sig_cache = Cpanel::Crypt::GPG::VendorKeys::TimestampCache->new();

    my $rollback = $sig_cache->check_cache_for_rollback(
        mirror      => $args->{mirror},
        url         => $args->{url},
        create_time => $sig_data->{create_time},
    );

    if ($rollback) {
        return _result( undef, 'Signature rollback detected.' );
    }
    else {
        $sig_cache->update_cache( mirror => $args->{mirror}, url => $args->{url}, create_time => $sig_data->{create_time}, );
        return _result( $sig_data, $message );    # Everything ok, pass data through to next check.
    }
}

sub _check_filename {
    my ( $sig_data, $message, $args ) = @_;

    if ( defined( $sig_data->{'notations'} ) && defined( $sig_data->{'notations'}->{'filename@gpg.notations.cpanel.net'} ) ) {
        my $file_note = $sig_data->{'notations'}->{'filename@gpg.notations.cpanel.net'};

        my $url = $args->{url};
        $url =~ s/\.bz2$//;

        if ( $file_note eq $url ) {
            return _result( $sig_data, $message );    # Everything ok, pass data through to next check.
        }
        else {
            return _result( undef, 'Filename notation (' . $file_note . ') does not match URL (' . $url . ').' );
        }
    }
    else {
        return _result( undef, 'Signature does not contain a filename notation.' );
    }
}

sub _result {
    my ( $success, $message ) = @_;
    return wantarray ? ( $success, $message ) : $success;
}

1;
