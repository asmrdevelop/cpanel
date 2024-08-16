package Cpanel::Crypt::GPG::VendorKeys;

# cpanel - Cpanel/Crypt/GPG/VendorKeys.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 NAME

Cpanel::Crypt::GPG::VendorKeys -- Key storage infrastucture for vendor PGP/GPG keys.

=head1 SYNOPSIS

 use Cpanel::Crypt::GPG::VendorKeys ();

 my ($success, $msg) = Cpanel::Crypt::GPG::VendorKeys::set_keys_from_url(
     vendor => "cpanel",
     category => "test",
     url => "https://mirror.secteamsix.dev.cpanel.net/gpgkeys/test-01.pub.key",
 );

 if (!$success) {
     print "Failure when setting keys: $msg\n";
 }

 my $keys = Cpanel::Crypt::GPG::VendorKeys::get_keys(
     vendor => "cpanel",
     categories => ["release", "test"]
 );

=head1 METHODS

=cut

use strict;
use warnings;

use Cpanel::Crypt::GPG::Import::Temp ();
use Cpanel::CachedDataStore          ();
use Cpanel::SecureDownload           ();

our $VERSION = 1;

=pod

B<_get_config_file( )> (private method)

Returns path for vendor key store.

=cut

sub _get_config_file {
    return '/var/cpanel/gpg/vendorkeys.yaml';
}

=pod

B<_get_vendor_keys( )> (private method)

Loads vendor key store.
Returns hash reference.

=cut

sub _get_vendor_keys {
    return Cpanel::CachedDataStore::fetch_ref( _get_config_file() );
}

=pod

B<_save_vendor_keys( \%vk_ref )> (private method)

Saves vendor key store. Creates directory if missing.

I<\%vk_ref> is a hash reference to the key data.

=cut

sub _save_vendor_keys {
    my ($vk_ref) = @_;
    require File::Basename;
    my $keydir = File::Basename::dirname( _get_config_file() );

    if ( !-d $keydir ) {
        require Cpanel::SafeDir::MK;
        Cpanel::SafeDir::MK::safemkdir( $keydir, 0700 );
    }

    return Cpanel::CachedDataStore::savedatastore( _get_config_file(), { mode => 0600, data => $vk_ref } );
}

=pod

B<set_keys( %args )>

Sets the local vendor keychain contents.

I<%args> can contain:

=over 4

=item * vendor

A scalar string containing the vendor name.
Required.

=item * category

A scalar string containing the vendor category.
Required.

=item * url

A scalar string containing the location where the keys came from.
Required.

=item * keys

A scalar string the keys to set.
Required.

=item * enabled

A boolean value. When set the category keychain is enabled.
Defaults to TRUE.

=item * interval

A scalar integer. Seconds between checks for new keys.
A zero value indicates I<always> check.
A negative value indicates I<never> check.
Defaults to 86400 seconds (1 day).

=back

Returns a list containing ($success, $message).

=cut

sub set_keys {
    my (%args) = @_;

    $args{interval} = defined( $args{interval} ) ? $args{interval} : 86400;    # 1 day, in seconds.
    $args{enabled}  = defined( $args{enabled} )  ? $args{enabled}  : 1;

    for my $a (qw{vendor category url keys}) {
        if ( !$args{$a} ) {
            return wantarray ? ( undef, "Argument '$a' is required." ) : undef;
        }
    }

    my %new_keys;
    my @ckeys = ( ref( $args{keys} ) eq 'ARRAY' ) ? @{ $args{keys} } : ( $args{keys} );

    my $gpg = Cpanel::Crypt::GPG::Import::Temp->new();

    if ( !$gpg ) {
        return wantarray ? ( undef, "Failed to create GPG object." ) : undef;
    }

    for my $ckey (@ckeys) {
        while ( $ckey =~ /(-----BEGIN PGP PUBLIC KEY BLOCK-----.*?-----END PGP PUBLIC KEY BLOCK-----)/gs ) {
            my $skey = $1;
            my ( $key_id, $msg ) = $gpg->get_key_id( key => $skey );

            if ( !$key_id ) {
                return wantarray ? ( undef, $msg ) : undef;
            }

            $new_keys{$key_id} = $skey;
        }
    }

    if ( !keys %new_keys ) {
        return wantarray ? ( undef, "No valid keys found." ) : undef;
    }

    my $vk_ref = _get_vendor_keys();

    # Update key data.

    $vk_ref->{ $args{vendor} }->{ $args{category} } = {
        url          => $args{url},
        keychain     => \%new_keys,
        enabled      => $args{enabled},
        interval     => $args{interval},
        noverify     => $args{noverify},
        last_updated => _get_current_time(),
    };

    # Version number indicates available settings
    $vk_ref->{__VERSION} = $VERSION;

    if ( _save_vendor_keys($vk_ref) ) {
        return wantarray ? ( 1, 'Success' ) : 1;
    }

    return wantarray ? ( undef, "Failed to save key store." ) : undef;
}

=pod

B<_get_current_time( )> (private method)

Returns current time, in seconds.

=cut

sub _get_current_time {
    return int(time);
}

=pod

B<set_keys_from_url( %args )>

Obtains a vendor keychain from a URL.
Sets the local vendor keychain to the contents of this.

I<%args> can contain:

=over 4

=item * vendor

A scalar string containing the vendor name.
Required.

=item * category

A scalar string containing the vendor category.
Required.

=item * url

A scalar string containing the URL of keys to set.
URL must be HTTPS/SSL.
Required.

=item * enabled

A boolean value. When set the category keychain is enabled.

=item * interval

A scalar integer. Seconds between checks for new keys.
A zero value indicates I<always> check.
A negative value indicates I<never> check.

=back

Returns a list containing ($success, $message).

=cut

sub set_keys_from_url {
    my (%args) = @_;

    for my $a (qw{vendor category url}) {
        if ( !$args{$a} ) {
            return wantarray ? ( undef, "Argument '$a' is required." ) : undef;
        }
    }

    my $url = $args{url};

    if ( ( !$args{noverify} ) && ( $url !~ /^https:\/\//i ) ) {
        return wantarray ? ( undef, "URL must use SSL." ) : undef;
    }

    my ( $ret, $download_data ) = Cpanel::SecureDownload::fetch_url(
        $url,
        ( 'timeout' => 60, 'no-check-certificate' => $args{noverify} )
    );

    if ( !$ret ) {

        # download_data will contain the error message upon failure
        return wantarray ? ( undef, $download_data ) : undef;
    }

    my ( $success, $msg ) = set_keys(
        vendor   => $args{vendor},
        category => $args{category},
        url      => $args{url},
        keys     => $download_data,
        enabled  => $args{enabled},
        interval => $args{interval},
        noverify => $args{noverify},
    );

    if ( !$success ) {
        return wantarray ? ( undef, "Failure when adding key: $msg" ) : undef;
    }

    return wantarray ? ( 1, "Successfully added key." ) : 1;
}

=pod

B<get_keys( %args )>

Returns a list of keys for a vendor.

I<%args> can contain:

=over 4

=item * vendor

A scalar string containing the vendor name.
Required.

=item * category || categories

A scalar string, or array reference of strings, containing the vendor categories.
One of these is required.

=back

Returns a hash reference containing keys belonging to the vendor, indexed by key ID.

=cut

sub get_keys {
    my (%args) = @_;

    if ( !$args{vendor} ) {
        return wantarray ? ( undef, "Argument 'vendor' is required." ) : undef;
    }

    if ( !( $args{category} || $args{categories} ) ) {
        return wantarray ? ( undef, "Argument 'category' or 'categories' is required." ) : undef;
    }

    if ( $args{category} && $args{categories} ) {
        return wantarray ? ( undef, "Both argument 'category' and 'categories' can not be used simultaneously." ) : undef;
    }

    my $argcat = $args{category} || $args{categories};
    my @cats   = ( ref($argcat) eq 'ARRAY' ) ? @{$argcat} : ($argcat);
    my $vk_ref = _get_vendor_keys();

    if ( !$vk_ref->{ $args{vendor} } ) {
        return wantarray ? ( undef, "Keys for vendor '" . $args{vendor} . "' not found." ) : undef;
    }

    my %keys;

    for my $cat (@cats) {
        if ( !$vk_ref->{ $args{vendor} }->{$cat} ) {
            next;    # skip over non-existent categories
        }

        if ( !$vk_ref->{ $args{vendor} }->{$cat}->{enabled} ) {
            next;    # skip over disabled keychains
        }

        for my $key ( keys %{ $vk_ref->{ $args{vendor} }->{$cat}->{keychain} } ) {
            $keys{$key} = $vk_ref->{ $args{vendor} }->{$cat}->{keychain}->{$key};
        }
    }

    return \%keys;
}

=pod

B<get_key_info>

Gets the type and vendor of a key based on the key's ID.

Returns scalar string containing the type of the key, or 'UNKNOWN' if nothing was found.

=cut

sub get_key_info {
    my ($keyid) = @_;
    my $keys = _get_vendor_keys();

    foreach my $vendor ( keys %{$keys} ) {

        # Out of band version/misc data is stored prefixed with '__'
        # These are not actual vendors
        if ( index( $vendor, '__' ) == 0 ) {
            next;
        }

        foreach my $type ( keys %{ $keys->{$vendor} } ) {
            return ( $vendor, $type ) if grep { $keyid eq $_ } keys %{ $keys->{$vendor}->{$type}->{keychain} };
        }
    }
    return ( 'UNKNOWN', 'UNKNOWN' );
}

sub download_public_keys {
    my %opts = @_;

    # Cpanel::Logger and Cpanel::Update::Logger have different method names.

    require Cpanel::Logger;
    $opts{logger} ||= Cpanel::Logger->new();
    my $warn  = $opts{logger}->can("warn")  ? 'warn'  : 'warning';
    my $error = $opts{logger}->can("error") ? 'error' : 'warn';

    if ( $opts{noverify} ) {
        $opts{logger}->info("WARNING: Hostname verification is disabled!");
        $opts{logger}->info("Can not ensure the legitimacy of downloaded keys.");
    }

    my $vk_ref = _get_vendor_keys();

    # Load list of keys to update from vendor keystore.

    my %update_keys;

    for my $vendor ( grep { index( $_, '__' ) != 0 } keys %{$vk_ref} ) {
        for my $category ( keys %{ $vk_ref->{$vendor} } ) {
            $update_keys{$vendor}->{$category}->{url}      = $vk_ref->{$vendor}->{$category}->{url};
            $update_keys{$vendor}->{$category}->{noverify} = $vk_ref->{$vendor}->{$category}->{noverify};
        }
    }

    # Force update of hardcoded cPanel key values.
    # This will be necessary if someone accidentally removed the cPanel keys from the datastore.

    for my $key ( @{ _get_pubkey_defaults() } ) {
        my $vendor   = $key->{vendor};
        my $category = $key->{category};
        my $url      = $key->{url};
        my $noverify = $key->{noverify};
        $update_keys{$vendor}->{$category}->{url}      = $url;
        $update_keys{$vendor}->{$category}->{noverify} = $noverify;
    }

    # Flatten list of keys to update.

    my @update_keys_list;

    for my $vendor ( keys %update_keys ) {
        for my $category ( keys %{ $update_keys{$vendor} } ) {
            my $key = {
                vendor   => $vendor,
                category => $category,
                url      => $update_keys{$vendor}->{$category}->{url},
                noverify => $update_keys{$vendor}->{$category}->{noverify},
            };

            push @update_keys_list, $key;
        }
    }

    # If we were passed an explicit list of keys to update, use that.
    # Otherwise, use the previously generated list.

    my $keys;

    if ( $opts{keys} ) {
        $keys = $opts{keys};
    }
    else {
        $keys = \@update_keys_list;
    }

    my $success = 1;

    for my $key ( @{$keys} ) {
        my $interval     = $vk_ref->{ $key->{vendor} }->{ $key->{category} }->{interval}     || 0;
        my $last_updated = $vk_ref->{ $key->{vendor} }->{ $key->{category} }->{last_updated} || 0;

        # If we've not reached our update interval, skip download unless forced
        # Intervals prior to __VERSION 1 are ignored

        my $current_time = _get_current_time();

        next if ( !$opts{force}
            && defined $vk_ref->{__VERSION}
            && $vk_ref->{__VERSION} == $VERSION
            && $current_time <= ( $interval + $last_updated )
            && $current_time >= $last_updated );

        my ( $succ, $msg ) = set_keys_from_url(
            vendor   => $key->{vendor},
            category => $key->{category},
            url      => $key->{url},
            noverify => $key->{noverify} || $opts{noverify},
        );

        if ($succ) {
            $opts{logger}->info("Retrieved public key from vendor: $key->{vendor}, category: $key->{category}, url: $key->{url}");
        }
        else {
            $opts{logger}->$warn("Unable to download public key from vendor: $key->{vendor}, category: $key->{category}, url: $key->{url}");
            $opts{logger}->info($msg);
            $success = 0;
        }
    }

    if ( !$success ) {
        $opts{logger}->$warn("Failed to download all specified public keys.");
    }

    return $success;
}

sub _get_pubkey_defaults {
    return [
        {
            url      => 'https://securedownloads.cpanel.net/cPanelPublicKey.asc',
            vendor   => 'cpanel',
            category => 'release',
        },
        {
            url      => 'https://securedownloads.cpanel.net/cPanelDevelopmentKey.asc',
            vendor   => 'cpanel',
            category => 'development',
        },
    ];
}

1;
