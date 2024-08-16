# cpanel - Whostmgr/Accounts/Create/ResellerWithoutDomain.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Accounts::Create::ResellerWithoutDomain;

use cPstrict;
use Carp                              ();
use AcctLock                          ();
use Cpanel::AcctUtils::AccountingLog  ();
use Cpanel::ConfigFiles               ();
use Cpanel::Exception                 ();
use Cpanel::FileUtils::Write          ();
use Cpanel::Finally                   ();
use Cpanel::SafeFile                  ();
use Cpanel::SysAccounts               ();
use Cpanel::Version::Full             ();
use Whostmgr::Accounts::Create::Utils ();
use Whostmgr::Accounts::IdTrack       ();
use Whostmgr::ACLS                    ();
use Whostmgr::API::1::Session         ();

=head1 NAME

Whostmgr::Accounts::Create::ResellerWithoutDomain

=head1 DESCRIPTION

Automated version of https://go.cpanel.net/how-to-create-a-whm-reseller-without-an-associated-domain

=head1 WARNING

If you create a reseller without a domain, certain parts of WHM will not function
for that user. These limitations exist both when logged in as that user B<and>
when you attempt to perform actions which affect that user.

=head1 FUNCTIONS

=head2 create( username => ..., password => ... )

Given a username and, optionally, a password, create a reseller that lacks a domain.
See the documentation mentioned above for more about this.

If no password is supplied, one will be generated automatically.

Returns:

  - Status - boolean
  - Reason - string
  - Output - string, for display in UI
  - Data - hash ref:
    - edit_privileges_url - string - A URL at which the server administrator
                                     may edit the new account's privileges

=cut

sub create {
    my %OPTS = @_;

    AcctLock::acctlock();
    my $unlock = Cpanel::Finally->new( sub { AcctLock::acctunlock(); } );

    my ( $status, $reason, $output, $data ) = _create(%OPTS);

    return ( $status, $reason, $output, $data );
}

=head2 _create()

Private implementation

=cut

sub _create {
    my %OPTS   = @_;
    my $output = '';

    if ( !Whostmgr::ACLS::hasroot() ) {
        return ( 0, "You must be root or have the 'all' acl to create a reseller." );
    }

    my $username = $OPTS{username} || $OPTS{user};
    if ( !length $username ) {
        return ( 0, 'No user name supplied: "username" is a required argument.' );
    }

    my $password = Whostmgr::Accounts::Create::Utils::get_password(%OPTS) || die;

    my $homedir = $OPTS{homedir} || "/home/$username";

    my ( $status, $reason, $uid, $gid ) = Whostmgr::Accounts::IdTrack::allocate();
    if ( !$status ) {
        return ( $status, $reason );
    }

    # Username validation also happens here
    eval {
        Cpanel::SysAccounts::add_system_user(
            $username,
            'uid'     => $uid,
            'gid'     => $gid,
            'shell'   => '/bin/bash',
            'homedir' => $homedir,
            'pass'    => $password,
        );
    };
    if ( my $exception = $@ ) {
        return ( 0, Cpanel::Exception::get_string($exception) );
    }

    _chmod( 0711, $homedir );

    my $res_fh;
    my $reslock = Cpanel::SafeFile::safeopen( $res_fh, '>>', $Cpanel::ConfigFiles::RESELLERS_FILE );
    if ( !$reslock ) {
        return ( 0, "Could not write to $Cpanel::ConfigFiles::RESELLERS_FILE: $!" );
    }

    print {$res_fh} "${username}:\n";
    Cpanel::SafeFile::safeclose( $res_fh, $reslock );

    my ( $cpuser_status, $cpuser_reason ) = write_user_file( username => $username, gid => $gid, overwrite => 1 );
    if ( !$cpuser_status ) {
        return ( $cpuser_status, $cpuser_reason );
    }

    my $priv_url;
    if ( $ENV{cp_security_token} ) {    # make path only (for use in existing browser session)
        $priv_url = "$ENV{cp_security_token}/scripts2/editres?user=$username";
    }
    else {                              # make full URL
        my %args = (
            user    => 'root',
            service => 'whostmgrd',
            app     => 'edit_reseller_name_servers_and_privileges',
        );
        my $metadata = {};
        my $data     = Whostmgr::API::1::Session::create_user_session( \%args, $metadata );
        if ( !$metadata->{result} ) {
            return ( 0, $metadata->{reason} );
        }
        $priv_url = $data->{url};
        $priv_url =~ s{editres}{editres\?user=$username};
    }

    $output .= "Password: $password\n";
    Cpanel::AcctUtils::AccountingLog::append_entry( "CREATERESELLERWITHOUTDOMAIN", [$username] );

    return (
        1,
        'OK',
        $output,
        {
            edit_privileges_url => $priv_url,
        },
    );
}

=head2 _chmod()

Private implementation

=cut

sub _chmod {
    my ( $mode, $dir ) = @_;
    return chmod $mode, $dir;
}

=head2 _chown()

Private implementation

=cut

sub _chown {
    my ( $uid, $gid, $file_or_fh ) = @_;
    return chown $uid, $gid, $file_or_fh;
}

=head2 write_user_file( username => ..., gid => ..., overwrite => ... )

Normally used internally by this module when creating a reseller without a domain,
but you may also call this function externally if you have a need.

Given C<username> (name, not id) and C<gid> (numeric) for the user, create
a minimal cpuser file sufficient to prevent most WHM operations that expect
one from failing. If C<overwrite> is specified and true, any existing cpuser
file for that user will be written; otherwise, an exception is thrown when
the file already exists.

Returns a boolean indicating success or failure.

=cut

sub write_user_file (%opts) {
    my $username   = delete( $opts{username} ) // Carp::confess('must provide username');
    my $gid        = delete( $opts{gid} )      // Carp::confess('must provide gid');
    my $write_func = delete( $opts{overwrite} ) ? \&Cpanel::FileUtils::Write::overwrite : \&Cpanel::FileUtils::Write::write;
    Carp::confess('unknown options') if %opts;

    my @cpuser_data = (
        [ CREATED_IN_VERSION => Cpanel::Version::Full::getversion() ],
        [ OWNER              => 'root' ],
        [ STARTDATE          => time ],
        [ USER               => $username ],
    );

    my $cpuser_file = "$Cpanel::ConfigFiles::cpanel_users/$username";

    eval {
        my $cpuser_fh = $write_func->(
            $cpuser_file,
            join( q<>, map { "$_->[0]=$_->[1]\n" } @cpuser_data ),
            0640,
        );
        _chown( 0, $gid, $cpuser_fh ) or die $!;
        close $cpuser_fh              or die $!;
    };
    if ( my $exception = $@ ) {
        return ( 0, Cpanel::Exception::get_string($exception) );
    }

    return 1;
}

1;
