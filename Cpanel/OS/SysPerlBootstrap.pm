package Cpanel::OS::SysPerlBootstrap;

# cpanel - Cpanel/OS/SysPerlBootstrap.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# NOTE: we do not use cpstrict here so the code can be easily ported to the installer and run on perl 5.10.1
use strict;
use warnings;

use constant CACHE_FILE        => '/var/cpanel/caches/Cpanel-OS';
use constant CACHE_FILE_CUSTOM => CACHE_FILE . '.custom';

=encoding utf-8

=head1 NAME

Cpanel::OS::SysPerlBootstrap - SysPerlBootstrap logic used by Cpanel::OS

=head1 DO NOT USE THIS MODULE DIRECTLY

This code is intended to be system and cpanel perl compatible and to be consumed only in very specific circumstances.

Instead use L<Cpanel::OS> directly, and as its POD outlines, do not do logic on the OS info to determine what it is you need.

=head1 FUNCTIONS

=head2 get_os_info ($iknowwhatimdoing)

Please use Cpanel::OS for your OS info needs.
This is an internal helper to Cpanel::OS to get the
- distro
- major
- minor
- build id

=cut

sub get_os_info {
    my ($iknowwhatimdoing) = @_;
    die("Please use Cpanel::OS for your OS info needs") unless ( $iknowwhatimdoing && $iknowwhatimdoing eq 'DO NOT USE THIS CALL' );

    my @os_info = _read_os_info_cache();
    return @os_info if @os_info;

    my ( $distro, $major, $minor, $build ) = _get_os_without_cache('redhat_first');

    if ( !defined $distro || !length $distro || !defined $major || !length $major || !defined $minor || !length $minor || !defined $build || !length $build ) {
        die sprintf( "Could not determine OS info (distro: %s, major: %s, minor: %s, build: %s)\n", $distro // '', $major // '', $minor // '', $build // '' );
    }

    _cache_os_info( $^O, $distro, $major, $minor, $build );

    return ( $^O, $distro, $major, $minor, $build );
}

=head2 _get_os_without_cache( $redhat_first = 0 )

This function should not be called outside CpKeyClt and here.
Instead use L<Cpanel::OS> directly.

=cut

sub _get_os_without_cache {
    my ($redhat_first) = @_;

    my @os;
    if ($redhat_first) {    # preserve existing behavior for Cpanel::OS
        @os = _read_redhat_release();
        @os = _read_os_release() unless scalar @os;
    }
    else {
        @os = _read_os_release();
        @os = _read_redhat_release() unless scalar @os;
    }

    return @os;
}

=head2 _read_os_info_cache()

Read the previous cached values from CACHE_FILE

=cut

sub _read_os_info_cache {

    # If we've cached the information, just use it.
    my $cache_mtime = ( lstat CACHE_FILE )[9] or return;

    my $custom_os = readlink CACHE_FILE_CUSTOM;

    # Do we need to cache bust?
    if ( !$custom_os ) {
        my $os_rel_mtime = ( stat("/etc/os-release") )[9];
        $os_rel_mtime //= ( stat("/etc/redhat-release") )[9];    # in the case of cloudlinux 6, we check against this instead

        # Bail out only if one of the release files is present since the cache file is suddenly our only valid source of truth.
        return if ( defined($os_rel_mtime) && $cache_mtime <= $os_rel_mtime );
    }

    return split /\|/, readlink(CACHE_FILE);
}

=head2 _read_os_release()

Internal helper to read /etc/os-release

=cut

sub _read_os_release {

    return unless -e '/etc/os-release';

    open( my $os_fh, "<", "/etc/os-release" ) or die "Could not open /etc/os-release for reading: $!\n";

    my ( $distro, $ver, $ver_id );
    while ( my $line = <$os_fh> ) {
        my ( $key, $value ) = split( qr/\s*=\s*/, $line, 2 );
        chomp $value;
        $value =~ s/\s.+//;
        $value =~ s/"\z//;
        $value =~ s/^"//;

        if ( !$distro && $key eq "ID" ) {
            $distro = $value;
        }
        elsif ( !$ver_id && $key eq "VERSION_ID" ) {
            $ver_id = $value;
        }
        elsif ( !$ver && $key eq "VERSION" ) {
            $ver = $value;
        }

        last if defined $distro && length $distro && defined $ver && length $ver && defined $ver_id && length $ver_id;
    }
    close $os_fh;

    # ver_id is often enough.
    my ( $major, $minor, $build ) = split( qr/\./, $ver_id );
    return unless $distro;    # We have to at a minimum have a distro name. All hope is lost otherwise.

    unless ( defined $major && length $major && defined $minor && length $minor && defined $build && length $build ) {
        my ( $ver_major, $ver_minor, $ver_build ) = split( qr/\./, $ver );
        $major //= $ver_major;
        $minor //= ( $ver_minor // 0 );
        $build //= ( $ver_build // 0 );
    }

    return ( $distro, $major, $minor, $build );
}

=head2 _read_redhat_release()

Internal helper to read /etc/redhat-release

=cut

sub _read_redhat_release {

    return unless -e '/etc/redhat-release';

    open( my $cr_fh, "<", "/etc/redhat-release" ) or die "Could not open /etc/redhat-release for reading: $!\n";
    my $line = <$cr_fh>;
    chomp $line;

    my ($distro) = $line =~ m/^(\w+)/i;
    $distro = lc($distro);
    $distro = 'rhel' if $distro eq 'red';

    my ( $major, $minor, $build ) = $line =~ m{\b([0-9]+)\.([0-9]+)\.([0-9]+)};
    if ( !defined $major || !length $major ) {
        ( $major, $minor ) = $line =~ m{\b([0-9]+)\.([0-9]+)};
    }
    if ( !defined $major || !length $major ) {
        ($major) = $line =~ m{\b([0-9]+)};
    }
    $minor //= 0;
    $build //= 0;

    return ( $distro, $major, $minor, $build );
}

=head2 _cache_os_info( $os, $distro, $major, $minor, $build )

Internal helper used to cache the current OS values.

=cut

sub _cache_os_info {
    my ( $os, $distro, $major, $minor, $build ) = @_;
    $> == 0 or return;

    mkdir '/var/cpanel',        0711;
    mkdir '/var/cpanel/caches', 0711;

    local $!;
    unlink CACHE_FILE;
    symlink "$os|$distro|$major|$minor|$build", CACHE_FILE;

    return 1;
}

1;
