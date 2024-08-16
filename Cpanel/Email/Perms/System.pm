package Cpanel::Email::Perms::System;

# cpanel - Cpanel/Email/Perms/System.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#------------------------------------------------------------------------------------------------
# NOTE: Keep the directory permissions and setup logic in sync with Whostmgr::Accounts::Create.
#------------------------------------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::Email::Constants ();
use Cpanel::Email::Perms     ();
use Cpanel::FileUtils::Open  ();
use Cpanel::Debug            ();
use Cpanel::ConfigFiles      ();
use Cpanel::PwCache          ();
use Cpanel::SV               ();

my @system_perms_value = (
    Cpanel::Email::Constants::VFILE_PERMS(),
    $Cpanel::Email::Perms::NEEDS_GID_MAIL,
    $Cpanel::Email::Perms::CREATE_OK,
);

# Exposed for mocking in tests:
our @_directories_to_secure = (
    $Cpanel::ConfigFiles::VFILTERS_DIR,
    $Cpanel::ConfigFiles::VALIASES_DIR,
    $Cpanel::ConfigFiles::VDOMAINALIASES_DIR,
);

# %SYSTEM_PERMS format:
#
# relative_file => [ PERMS, GROUP_CONST, CREATE_CONST ];
#
my %SYSTEM_PERMS = map { ( "$_/%domain%" => \@system_perms_value ) } @_directories_to_secure;

my $mail_gid;

#
# ensure_domain_system_perms is expected to run as root.
# We do not check this because it would be very expensive in a loop.
# Please take approiate care when calling this function.
#
sub ensure_domain_system_perms {
    my ( $target_uid, $domain ) = @_;

    die "Need 2 args!" if !length $domain;

    $mail_gid ||= ( Cpanel::PwCache::getpwnam('mail') )[3];

    foreach my $path ( keys %SYSTEM_PERMS ) {
        my $perm_keys = $SYSTEM_PERMS{$path};
        $path =~ s/\%(?:[^\%]+)\%/$domain/g;
        Cpanel::SV::untaint($path);
        my ( $mode, $uid, $gid ) = ( stat($path) )[ 2, 4, 5 ];

        if ( !defined $gid ) {
            if ( $perm_keys->[$Cpanel::Email::Perms::FIELD_CREATE] ) {    # Create ok
                if ( Cpanel::FileUtils::Open::sysopen_with_real_perms( my $touch_fh, $path, 'O_WRONLY|O_CREAT|O_EXCL', $perm_keys->[$Cpanel::Email::Perms::FIELD_PERMS] ) ) {
                    print "Created $path\n" if $Cpanel::Email::Perms::VERBOSE;
                    ( $mode, $uid, $gid ) = ( stat($touch_fh) )[ 2, 4, 5 ];
                    close($touch_fh);
                }
                else {
                    Cpanel::Debug::log_warn("Failed to create $path: $!");
                    return;
                }
            }
            else {
                return;
            }
        }

        my $target_mode = sprintf '%04o', $perm_keys->[$Cpanel::Email::Perms::FIELD_PERMS] & 07777;
        $mode = sprintf '%04o', $mode & 07777;
        if ( $mode != $target_mode ) {
            if ( chmod $perm_keys->[$Cpanel::Email::Perms::FIELD_PERMS], $path ) {
                print "Fixed permissions on $path : was ($mode), now ($target_mode)\n" if $Cpanel::Email::Perms::VERBOSE;
            }
            else {
                Cpanel::Debug::log_warn("Failed to chmod ($target_mode): $path: $!");
            }
        }
        if ( $gid != $mail_gid || $uid != $target_uid ) {
            if ( chown $target_uid, $mail_gid, $path ) {
                print "Fixed ownership of $path : was (uid=$uid,gid=$gid), now (uid=$target_uid,gid=$mail_gid)\n" if $Cpanel::Email::Perms::VERBOSE;
            }
            else {
                Cpanel::Debug::log_warn("Failed to chown ($target_uid,$mail_gid): $path: $!");
            }
        }
    }

    return;
}

sub ensure_system_perms {
    require Cpanel::Mkdir;
    require Cpanel::FileUtils::Access;
    for my $dir (@_directories_to_secure) {
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $dir, Cpanel::Email::Constants::VDIR_PERMS );
        Cpanel::FileUtils::Access::ensure_mode_and_owner( $dir, Cpanel::Email::Constants::VDIR_PERMS, 0, 'mail' );
    }
    return;
}
1;
