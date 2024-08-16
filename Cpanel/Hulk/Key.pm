package Cpanel::Hulk::Key;

# cpanel - Cpanel/Hulk/Key.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Hulk ();

use constant _ENOENT => 2;

my $key_cache = {};

=encoding utf-8

=head1 NAME

Cpanel::Hulk::Key - Lookup keys needed to connect to cphulkd

=head1 SYNOPSIS

    use Cpanel::Hulk::Key ();
    use Cpanel::Hulk      ();

    my $cphulk = Cpanel::Hulk->new();

    if ( $cphulk->connect() && $cphulk->register( 'cpdavd', Cpanel::Hulk::Key::cached_fetch_key('cpdavd') ) ) {
        # you are in
    }

=head1 DESCRIPTION

This module was broken out of Cpanel::Hulk so it can be used inside of
Cpanel::Hulk callers as well as Cpanel::Hulkd::Processor without loading
all the client code.

=cut

=head2 get_key_path($app)

Returns the path to the key file on the filesystem for a given app.

=cut

sub get_key_path {
    my ($app) = @_;

    $app =~ tr/\///d;

    return $app ? $Cpanel::Config::Hulk::app_key_path . '/' . $app : '';    # Must always return something defined
}

=head2 getkey($app)

Returns the contents of key file on the filesystem for a given app.

=cut

sub getkey {
    return ( _get_key_and_mtime(@_) )[0];
}

=head2 cached_fetch_key($app)

The same as getkey but will use a memory cache if it is available.

=cut

sub cached_fetch_key {
    my ($app) = @_;

    if (   $key_cache->{$app}
        && $key_cache->{$app}{'disk_mtime'} >= ( ( stat( get_key_path($app) ) )[9] || 0 ) ) {
        return $key_cache->{$app}{'key'};
    }

    my ( $key, $mtime ) = _get_key_and_mtime($app);
    if ($key) {
        $key_cache->{$app} = { 'disk_mtime' => $mtime, 'key' => $key };
    }
    return $key;
}

sub _get_key_and_mtime {
    my ($app) = @_;

    my $keyfile = get_key_path($app);
    my ( $key, $mtime );

    if ( open my $hk_fh, '<', $keyfile ) {
        $mtime = ( stat($hk_fh) )[7];
        chomp( $key = readline $hk_fh );
        close $hk_fh;
    }
    else {
        my $err = $!;

        # Skip ENOENT warnings during install. They are expected as we
        # haven't installed the keys yet, and the warnings just clutter
        # the install log.
        if ( !$ENV{'CPANEL_BASE_INSTALL'} || $! != _ENOENT() ) {
            my $err = $!;
            require Cpanel::Debug;
            Cpanel::Debug::log_die("Unable to read $keyfile [UID $> GID $)]: $err");
        }

        return;
    }

    return ( $key, $mtime );
}

1;
