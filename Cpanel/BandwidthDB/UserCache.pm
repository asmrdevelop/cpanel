package Cpanel::BandwidthDB::UserCache;

# cpanel - Cpanel/BandwidthDB/UserCache.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This datastore exists to provide a quick, cheap cache of the current
# month’s data transfer total per user. It is valuable for the cPanel
# front page.
#----------------------------------------------------------------------

use strict;

use Errno               ();
use Cpanel::Exception   ();
use Cpanel::ConfigFiles ();
use Cpanel::DateUtils   ();
use Cpanel::LoadFile    ();
use Cpanel::LoadModule  ();

#for test
our $_DIR;

BEGIN {
    *_DIR = \$Cpanel::ConfigFiles::BANDWIDTH_CACHE_DIRECTORY;

    die 'Need _DIR!' if !$_DIR;
}

#used in test
sub _get_path_for_user_file {
    my ($user) = @_;

    return "$_DIR/$user";
}

#overridden in test
sub _now { return time }

#NOTE: In the interest of speed, this does NOT validate.
sub read_if_mtime_is_this_month {
    my ($user) = @_;

    my $path = _get_path_for_user_file($user);

    local $!;
    my $mtime = ( stat($path) )[9];

    if ($!) {
        return undef if $! == Errno::ENOENT();
        die Cpanel::Exception::create( 'IO::StatError', [ error => $!, path => $path ] );
    }

    if ( Cpanel::DateUtils::timestamp_is_in_this_month($mtime) ) {
        return Cpanel::LoadFile::load($path);
    }

    return undef;
}

#NOTE: In the interest of speed, this does NOT validate.
sub write {
    my ( $user, $total ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::SafeDir::MK');
    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Access');
    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Write');

    my $path = _get_path_for_user_file($user);
    Cpanel::SafeDir::MK::safemkdir( $_DIR, '0711' ) if !-d $_DIR;

    Cpanel::FileUtils::Write::overwrite( $path, $total );
    Cpanel::FileUtils::Access::ensure_mode_and_owner(
        $path,
        0640,
        'root',
        $user,
    );

    return;
}

sub remove {
    my ($user) = @_;

    my $path = _get_path_for_user_file($user);

    local ( $@, $! );
    require Cpanel::Autodie;
    return Cpanel::Autodie::unlink_if_exists($path);
}

sub rename {
    my ( $olduser, $newuser ) = @_;

    local ( $@, $! );
    require Cpanel::Autodie::More;

    return Cpanel::Autodie::More::rename_nondir_politely(
        map { _get_path_for_user_file($_) } (
            $olduser,
            $newuser,
        ),
    );
}

1;
