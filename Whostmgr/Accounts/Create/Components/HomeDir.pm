package Whostmgr::Accounts::Create::Components::HomeDir;

# cpanel - Whostmgr/Accounts/Create/Components/HomeDir.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::Accounts::Create::Components::HomeDir

=head1 SYNOPSIS

    use 'Whostmgr::Accounts::Create::Components::HomeDir';
    ...

=head1 DESCRIPTION

Moves any non-directory out of the way, and creates the new user's homedir.

=cut

use cPstrict;

use parent 'Whostmgr::Accounts::Create::Components::Base';

use constant pretty_name => "Home Directory";

use Cpanel::PwCache                   ();
use Cpanel::SafeSync::UserDir         ();
use Whostmgr::UI                      ();
use Cpanel::SafetyBits::Chown         ();
use Cpanel::SysAccounts               ();
use Whostmgr::Accounts::Create::Utils ();

our $SKEL_DIR = 'cpanel3-skel';

sub _run ( $output, $user = {} ) {

    if ( -e $user->{'homedir'} && !-d _ ) {
        $output .= "Moving $user->{'homedir'} out of the way so the home directory can be created!\n" if !$Whostmgr::UI::nohtml;
        rename( $user->{'homedir'}, "$user->{'homedir'}.account_creation_move_away" );
    }

    mkdir( $user->{'homedir'}, Cpanel::SysAccounts::homedir_perms() );

    Cpanel::SafetyBits::Chown::safe_chown( $user->{'uid'}, $user->{'gid'}, $user->{'homedir'} );    #safe (parent is owned by root)

    _install_skel_files( 'user' => $user->{'user'}, 'creator' => $user->{'creator'}, 'output_ref' => $output );

    Whostmgr::Accounts::Create::Utils::set_up_new_user_homedir(
        @{$user}{qw( user  domain  mailbox_format  hascgi )},
    );

    require Cpanel::FileProtect::Queue::Adder;

    # Enable fileprotect on subdomain directories if appropriate
    Cpanel::FileProtect::Queue::Adder->add( $user->{'user'} );
    $user->{'tasks'}{'modules'}{'FileProtectTasks'} = 1;
    push @{ $user->{'tasks'}{'schedule'} }, [ 'fileprotect_sync_user_homedir', { 'delay_seconds' => 5 } ];
    return 1;
}

sub _install_skel_files {
    my (%OPTS) = @_;

    my $user       = $OPTS{'user'};
    my $creator    = $OPTS{'creator'};
    my $output_ref = $OPTS{'output_ref'};
    my ( $creator_uid, $creator_gid, $creator_homedir ) = ( Cpanel::PwCache::getpwnam_noshadow($creator) )[ 2, 3, 7 ];
    my ( $user_uid, $user_gid, $user_homedir )          = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 2, 3, 7 ];

    if ( -e "$creator_homedir/$SKEL_DIR" && _skel_has_non_default_files("$creator_homedir/$SKEL_DIR") && $user_homedir && -d $user_homedir ) {
        if ( -l $creator_homedir . "/$SKEL_DIR" ) {
            $$output_ref .= Whostmgr::UI::setstatus("Skipping copy of skel files from $creator_homedir/$SKEL_DIR/. Symlinks are not allowed.");
            $$output_ref .= Whostmgr::UI::setstatusdone();
        }
        else {
            $$output_ref .= Whostmgr::UI::setstatus("Copying skel files from $creator_homedir/$SKEL_DIR/ to $user_homedir/");
            Cpanel::SafeSync::UserDir::sync_to_userdir(
                'source'                => $creator_homedir . "/$SKEL_DIR",
                'target'                => $user_homedir,
                'setuid'                => [ $user_uid, $user_gid ],
                'wildcards_match_slash' => 0,
                'overwrite_public_html' => 1,
                'source_setuid'         => $creator_uid > 0 ? [ $creator_uid, $creator_gid ] : 0,
            );

            $$output_ref .= Whostmgr::UI::setstatusdone();
        }
    }
    return 1;
}

sub _skel_has_non_default_files {
    my $skel_dir = shift;

    # if it is more than ./public_html and ./public_ftp we need to install them
    if ( opendir( my $skdh, $skel_dir ) ) {
        my @base_files;
        for ( 0 .. 5 ) { push @base_files, readdir($skdh); }
        @base_files = grep { $_ ne '.' && $_ ne '..' && $_ ne 'public_html' && $_ ne 'public_ftp' } @base_files;
        closedir($skdh);

        return 1 if @base_files;

        foreach my $subdir ( 'public_html', 'public_ftp' ) {
            if ( opendir( my $skdh_pub, $skel_dir . "/" . $subdir ) ) {
                my @sub_base_files;
                for ( 0 .. 3 ) { push @sub_base_files, readdir($skdh_pub); }
                @sub_base_files = grep { $_ ne '.' && $_ ne '..' } @sub_base_files;

                return 1 if @sub_base_files;
                closedir($skdh_pub);
            }
        }
    }

    return 0;
}

1;
