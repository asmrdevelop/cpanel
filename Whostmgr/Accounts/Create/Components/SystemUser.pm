package Whostmgr::Accounts::Create::Components::SystemUser;

# cpanel - Whostmgr/Accounts/Create/Components/SystemUser.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::Accounts::Create::Components::SystemUser

=head1 SYNOPSIS

    use 'Whostmgr::Accounts::Create::Components::SystemUser';
    ...

=head1 DESCRIPTION

This module holds the unix account creation logic.

=cut

use cPstrict;

use Try::Tiny;

use parent 'Whostmgr::Accounts::Create::Components::Base';

use AcctLock                           ();
use Cpanel::Auth::Generate             ();
use Cpanel::PwCache                    ();
use Cpanel::SafetyBits::Chown          ();
use Cpanel::SysAccounts                ();
use Whostmgr::Accounts::IdTrack        ();
use Whostmgr::Accounts::Shell::Default ();

use constant pretty_name => "System User";

=head2 _run()

Gets/sets the default shell for the user, then...

Allocate a UID/GID and create the actual user on the system.

Update the user hash to include the UID, GID, and homedir that we
actually created.

=cut

sub _run ( $output, $user = {} ) {

    $user->{'shell'} = Whostmgr::Accounts::Shell::Default::get_default_shell( $user->{'_cpconf'} );

    if ( $user->{'hasshell'} eq 'n' ) {
        $user->{'shell'} = $Cpanel::Shell::NO_SHELL;
        $$output .= "Removing Shell Access ($user->{'hasshell'})\n";
    }
    else {
        $$output .= "Adding Shell Access ($user->{'hasshell'})\n";
        if ( $user->{'shell'} eq $Cpanel::Shell::JAIL_SHELL ) {
            $$output .= "... Jail Shell Enabled (Use jailshell as the default shell for all new accounts and modified accounts is enabled in TweakSettings)....\n";
        }
    }

    my $crypted_password = Cpanel::Auth::Generate::generate_password_hash( $user->{'pass'} );
    AcctLock::acctlock();
    my ( $status, $statusmsg, $uid, $gid ) = Whostmgr::Accounts::IdTrack::allocate( { 'uid' => $user->{'uid'}, 'gid' => $user->{'gid'} } );

    if ($status) {
        $statusmsg = '';
        try {
            $status = Cpanel::SysAccounts::add_system_user(
                $user->{'user'},
                'crypted_pass' => $crypted_password,
                'uid'          => $uid,
                'gid'          => $gid,

                'homedir'      => $user->{'homedir'},
                'homedir_root' => $user->{'homeroot'},

                'shell' => $user->{'shell'}
            );
        }
        catch {
            require Cpanel::Exception;
            $statusmsg = Cpanel::Exception::get_string($_);
        };

        if ( $status && !$statusmsg ) {
            $$output .= "Success";
        }
        else {
            $statusmsg = "Unable to add user $user->{'user'}: add_system_user failed" . ( $statusmsg ? " due to an error: $statusmsg" : () );
        }
    }
    AcctLock::acctunlock();

    die $statusmsg if $statusmsg;

    @$user{ 'uid', 'gid', 'homedir' } = ( Cpanel::PwCache::getpwnam_noshadow( $user->{'user'} ) )[ 2, 3, 7 ];

    if ( !$user->{'uid'} ) {
        die "Unable to add user $user->{'user'}";
    }
    if ( !$user->{'gid'} ) {
        die "Unable to add group $user->{'user'}";
    }

    Cpanel::SafetyBits::Chown::safe_chown(
        $user->{'uid'},
        $user->{'gid'},
        $user->{'homedir'}
    );    #safe since we own /home or the base

    return 1;
}

1;
