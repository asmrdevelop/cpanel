package Cpanel::Email::Config::Perms;

# cpanel - Cpanel/Email/Config/Perms.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache  ();
use Cpanel::AdminBin ();
use Cpanel::Debug    ();
my $mail_gid;

#Some old tests depend on being able to do things as root that should only ever
#be done as a user.
# TO_BE_CALLED_AS_ROOT_FOR_THE_SAKE_OF_SOME_OLD_TESTS__PLEASE_DO_NOT_USE_FOR_NEW_TESTS;
our $_ALLOW_secure_mail_db_file_FOR_OLD_TEST;

#exposed for testing only
our $_secure_mail_db_file_target_mode = 0640;

#The usefulness of this is pretty "focused": if the passed-in file handle
#isn't owned by $user:mail and doesn't have $_secure_mail_db_file_target_mode
#permissions, we call admin:mx::NULLIFY($domain).
#
sub secure_mail_db_file {
    my ( $domain, $fh ) = @_;

    #Since this does an admin call, which can't happen as root,
    #check for that mistake up-front.
    if ( !$_ALLOW_secure_mail_db_file_FOR_OLD_TEST ) {
        die "Cannot be called as root!" if !$>;
    }

    # $mail_gid only needs to be resolved once.
    # Since this function can be called multiple times in one run,
    # we only look it up once.
    $mail_gid ||= ( Cpanel::PwCache::getpwnam('mail') )[3];

    my ( $file_mode, $file_gid ) = ( stat $fh )[ 2, 5 ];

    $file_mode = $file_mode & 07777;

    if ( $mail_gid != $file_gid || $file_mode != $_secure_mail_db_file_target_mode ) {
        require Cpanel::AdminBin;
        my $adminbin_return = Cpanel::AdminBin::run_adminbin_with_status( 'mx', 'NULLIFY', $domain );

        if ( !$adminbin_return->{'status'} ) {
            my $msg = join( ' ', $adminbin_return->{'statusmsg'} || '', $adminbin_return->{'error'} || '' );
            Cpanel::Debug::log_warn($msg);
        }

    }

    return;
}

1;
