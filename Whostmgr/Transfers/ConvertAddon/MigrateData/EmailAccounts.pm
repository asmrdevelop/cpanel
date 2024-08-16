package Whostmgr::Transfers::ConvertAddon::MigrateData::EmailAccounts;

# cpanel - Whostmgr/Transfers/ConvertAddon/MigrateData/EmailAccounts.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Try::Tiny;

use parent qw(Whostmgr::Transfers::ConvertAddon::MigrateData);

use File::Spec                               ();
use Cpanel::Email::Perms::User               ();
use Whostmgr::Transfers::ConvertAddon::Utils ();
use Cpanel::Exception                        ();
use Cpanel::LoadFile                         ();
use Cpanel::AccessIds::ReducedPrivileges     ();
use Cpanel::PwCache                          ();

sub new {
    my ( $class, $opts ) = @_;

    my $self = $class->SUPER::new($opts);
    $self->{'from_homedir'} = Whostmgr::Transfers::ConvertAddon::Utils::gethomedir_or_die( $self->{'from_username'} );
    $self->{'to_homedir'}   = Whostmgr::Transfers::ConvertAddon::Utils::gethomedir_or_die( $self->{'to_username'} );

    return $self;
}

sub copy_email_accounts_for_domain {
    my ( $self, $domain ) = @_;
    if ( !$domain ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a domain name' );    ## no extract maketext (developer error message. no need to translate)
    }

    my $old_maildir = File::Spec->catdir( $self->{'from_homedir'}, 'mail', $domain );
    if ( -d $old_maildir ) {
        my $new_maildir = File::Spec->catdir( $self->{'to_homedir'}, 'mail', $domain );
        $self->safesync_dirs( { 'source_dir' => $old_maildir, 'target_dir' => $new_maildir } );
    }

    my $old_mailetc = File::Spec->catdir( $self->{'from_homedir'}, 'etc', $domain );
    if ( -d $old_mailetc ) {
        my $new_mailetc = File::Spec->catdir( $self->{'to_homedir'}, 'etc', $domain );
        $self->safesync_dirs( { 'source_dir' => $old_mailetc, 'target_dir' => $new_mailetc } );
        $self->_update_email_passwd_file( $domain, File::Spec->catfile( $new_mailetc, 'passwd' ) );
    }

    # Also copy the mail users' CalDAV and CardDAV data
    if ( opendir( my $cd, $self->{'from_homedir'} . '/.caldav/' ) ) {
        my @addon_accts = grep { /\@$domain$/ && -d $self->{'from_homedir'} . '/.caldav/' . $_ } readdir($cd);
        closedir($cd);
        foreach my $acct (@addon_accts) {
            $self->safesync_dirs( { 'source_dir' => $self->{'from_homedir'} . '/.caldav/' . $acct, 'target_dir' => $self->{'to_homedir'} . '/.caldav/' . $acct } );
        }
    }

    Cpanel::Email::Perms::User::ensure_all_perms( $self->{'to_homedir'} );

    return 1;
}

sub _update_email_passwd_file {
    my ( $self, $domain, $passwd_file ) = @_;
    my ( $to_user_uid, $to_user_gid ) = ( Cpanel::PwCache::getpwnam( $self->{'to_username'} ) )[ 2, 3 ];

    try {
        Cpanel::AccessIds::ReducedPrivileges::call_as_user(
            sub {
                my $passwd_file_contents = Cpanel::LoadFile::load($passwd_file);
                open my $passwd_fh, '>', $passwd_file
                  or die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $passwd_file, error => $!, mode => '>' ] );
                foreach ( split( /\n/, $passwd_file_contents ) ) {
                    my ( $user, $pass, undef, undef, $owner ) = split /:/, $_;

                    # Update the UID, GID, Directory, and Shell in the passwd file
                    print {$passwd_fh} join(
                        ':',
                        $user,
                        $pass,
                        $to_user_uid,
                        $to_user_gid,
                        $owner,
                        File::Spec->catdir( $self->{'to_homedir'}, 'mail', $domain, $user ),
                        $self->{'to_homedir'}
                    ) . "\n";
                }
                close $passwd_fh;
            },
            $to_user_uid,
            $to_user_gid
        );
    }
    catch {
        $self->add_warning( 'Failed to update the mail passwd entries for the domain: ' . Cpanel::Exception::get_string_no_id($_) );
    };

    return 1;
}

1;
