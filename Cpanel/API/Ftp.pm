package Cpanel::API::Ftp;

# cpanel - Cpanel/API/Ftp.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                       ();
use Cpanel::ConfigFiles          ();
use Cpanel::AdminBin             ();
use Cpanel::AdminBin::Call       ();
use Cpanel::API                  ();
use Cpanel::ExpVar::Utils        ();
use Cpanel::Debug                ();
use Cpanel::Fcntl                ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::FtpUtils::Server     ();
use Cpanel::Locale ('lh');
use Cpanel::LoadModule                ();
use Cpanel::Math                      ();
use Cpanel::SafeDir                   ();
use Cpanel::SafeDir::MK               ();
use Cpanel::SafeFile                  ();
use Cpanel::Validate::VirtualUsername ();
use Cpanel::Quota                     ();
use Cpanel::ConfigFiles               ();

my $ftp_role = {
    needs_role => "FTP",
};

my $ftp_role_allow_demo = {
    %$ftp_role,
    allow_demo => 1,
};

my $ftp_role_and_ftpaccts_feature = {
    %$ftp_role,
    needs_feature => "ftpaccts",
};

my $ftp_role_and_ftpsetup_feature = {
    %$ftp_role,
    needs_feature => "ftpsetup",
};

my $ftp_role_and_ftpsetup_feature_allow_demo = {
    %$ftp_role_and_ftpsetup_feature,
    allow_demo => 1,
};

our %API = (

    # This should NOT require the FTP role because it’s fine
    # for an API caller to query whether FTP is enabled or not.
    get_ftp_daemon_info => undef,

    # TODO: These should really be needs_service => 'ftp' but service checking in the API layer isn't implemented yet
    list_ftp                      => $ftp_role_allow_demo,
    list_ftp_with_disk            => $ftp_role_allow_demo,
    set_homedir                   => $ftp_role_and_ftpaccts_feature,
    add_ftp                       => $ftp_role_and_ftpaccts_feature,
    delete_ftp                    => $ftp_role_and_ftpaccts_feature,
    passwd                        => $ftp_role_and_ftpaccts_feature,
    get_quota                     => $ftp_role_allow_demo,
    set_quota                     => $ftp_role,
    list_sessions                 => $ftp_role_and_ftpsetup_feature_allow_demo,
    kill_session                  => $ftp_role_and_ftpsetup_feature,
    get_welcome_message           => $ftp_role_allow_demo,
    set_welcome_message           => $ftp_role_and_ftpsetup_feature,
    server_name                   => $ftp_role_allow_demo,
    allows_anonymous_ftp          => $ftp_role_allow_demo,
    allows_anonymous_ftp_incoming => $ftp_role_allow_demo,
    set_anonymous_ftp             => $ftp_role_and_ftpsetup_feature,
    set_anonymous_ftp_incoming    => $ftp_role_and_ftpsetup_feature,
    get_port                      => $ftp_role_allow_demo,
);

our $VERSION = '1.6';

=head1 NAME

UAPI Ftp

=cut

##############################

=head1 SUBROUTINES

=head2 Ftp::ftp_exists( %args )

Determine if an ftp account already exists

param:

user - the ftp account that we want to check for existence

=cut

sub ftp_exists {
    my ( $args, $result ) = @_;
    my $account = $args->get('user');
    my $domain  = $args->get('domain');

    if ( !length $account ) {
        $result->error('You must specify a user name.');
        return;
    }

    ( $account, $domain ) = _normalize_user_and_domain( $account, $domain );

    my $does_exist = _lookup_ftp_acct( $account, $domain );

    unless ($does_exist) {
        $result->error( 'The FTP account “[_1]” at domain “[_2]” does not exist.', $account, $domain );
        return;
    }

    return 1;
}

sub list_ftp {
    my ( $args, $result ) = @_;
    my @PARRY = _listftp();

    my @ACCTTYPE_SKIP_LIST    = split( /\|/, $args->get('skip_acct_types')    || q{} );
    my @ACCTTYPE_INCLUDE_LIST = split( /\|/, $args->get('include_acct_types') || q{} );

    my @RSD;
    foreach my $acct (@PARRY) {
        my $accttype = $acct->{'type'};

        next if ( scalar @ACCTTYPE_SKIP_LIST    && grep( /^$accttype$/,  @ACCTTYPE_SKIP_LIST ) );
        next if ( scalar @ACCTTYPE_INCLUDE_LIST && !grep( /^$accttype$/, @ACCTTYPE_INCLUDE_LIST ) );
        push @RSD, $acct;
    }
    $result->data( \@RSD );
    return 1;
}

sub list_ftp_with_disk {
    my ( $args, $result ) = @_;

    my $locale = Cpanel::Locale->get_handle();
    my %ACCTS  = _fullftplist();
    my $regex  = $args->get('regex');

    my @ACCTTYPE_SKIP_LIST    = split( /\|/, $args->get('skip_acct_types')    || q{} );
    my @ACCTTYPE_INCLUDE_LIST = split( /\|/, $args->get('include_acct_types') || q{} );

    my $dirhtml = $args->get('dirhtml');
    if ($dirhtml) {
        $dirhtml =~ s/\]/\>/g;
        $dirhtml =~ s/\[/\</g;
    }

    my @TFTPS;
    foreach my $acct ( sort keys %ACCTS ) {
        next if ( defined $regex && $regex && $acct !~ /$regex/i );

        my $accttype = $ACCTS{$acct}{'type'} || '';
        next if ( scalar @ACCTTYPE_SKIP_LIST    && grep( /^$accttype$/,  @ACCTTYPE_SKIP_LIST ) );
        next if ( scalar @ACCTTYPE_INCLUDE_LIST && !grep( /^$accttype$/, @ACCTTYPE_INCLUDE_LIST ) );

        my $delable = 1;
        if ( $accttype eq 'anonymous' ) { $delable = 0; }
        my $diskquota = Cpanel::Math::floatto( $ACCTS{$acct}{'megquota'}, 2 );
        if ( $ACCTS{$acct}{'megquota'} == 0 ) {
            my $infinityimg = $args->get('infinityimg');
            if ($infinityimg) {
                $diskquota = '<img src="' . $infinityimg . '" border="0" align="absmiddle">';
            }
            elsif ( $args->get('infinitylang') ) {
                $diskquota = '∞';
            }
            else {
                $diskquota = 'unlimited';
            }
        }
        my $homehtml;
        if ($dirhtml) {
            if ( $ACCTS{$acct}{'dir'} =~ /^($Cpanel::homedir|$Cpanel::abshomedir)($|\/)/ ) {
                $homehtml = $dirhtml . '/' . $ACCTS{$acct}{'reldir'};
            }
            else {
                $homehtml = $ACCTS{$acct}{'dir'};
            }
        }
        if ( !$accttype || $accttype eq '' ) {
            $accttype = 'anonymous';
        }
        push(
            @TFTPS,
            {
                'login'             => $acct,                          # Keeping this one for backward compatibility.
                'user'              => $acct,                          # Prefer to use this field now to match with what is returned by list_ftp()
                'accttype'          => $accttype,                      # Keeping this one for backward compatibility.
                'type'              => $accttype,                      # Prefer to use this field now to match with what is returned by list_ftp()
                'deleteable'        => $delable,
                'htmldir'           => $homehtml,
                'reldir'            => $ACCTS{$acct}{'reldir'},
                'serverlogin'       => $ACCTS{$acct}{'serverlogin'},
                'dir'               => $ACCTS{$acct}{'dir'},
                '_diskused'         => Cpanel::Math::floatto( $ACCTS{$acct}{'megused'},  2 ),
                '_diskquota'        => Cpanel::Math::floatto( $ACCTS{$acct}{'megquota'}, 2 ),
                'diskused'          => Cpanel::Math::floatto( $ACCTS{$acct}{'megused'},  2 ),
                'diskquota'         => $diskquota,
                'humandiskused'     => Cpanel::Math::_toHumanSize( $ACCTS{$acct}{'used'},  1 ),
                'humandiskquota'    => Cpanel::Math::_toHumanSize( $ACCTS{$acct}{'quota'}, 1 ),
                'diskusedpercent'   => $ACCTS{$acct}{'percent'},
                'diskusedpercent20' => Cpanel::Math::roundto( $ACCTS{$acct}{'percent'}, 20, 100 ),
            }
        );
    }

    $result->data( \@TFTPS );
    return 1;
}

#Parameters:
#
#   user    - the name (without domain) of the FTP account to create
#       - must pass Cpanel::Validate::VirtualUsername when combined with the domain
#       - whitespace is stripped
#
#   domain  - The domain for the FTP account. If not specified,
#             the cPanel user's primary domain will be used.
#
#   homedir  - (optional) the new FTP account's directory to set:
#       - defaults to $cphomedir/$user if not given
#       - whitespace and double-dots are stripped
#       - if q<>, directory will be $cphomedir/public_html
#       - otherwise, directory is $cphomedir/$ftpdir
#
sub set_homedir {
    my ( $args, $result ) = @_;
    my ( $user, $domain, $ftpdir ) = $args->get(qw(user domain homedir));

    if ( !length $user ) {
        $result->error('You must specify a user name.');
        return;
    }

    ( $user, $domain ) = _normalize_user_and_domain( $user, $domain );

    if ( defined $ftpdir ) {
        $ftpdir =~ s/\.\.//g;

        if ( $ftpdir eq q<> ) {
            $ftpdir = "public_html";
        }
    }
    elsif ( defined $domain ) {
        $ftpdir = $user . '@' . $domain;
    }
    else {
        $ftpdir = $user;
    }

    # This validation is also done by the adminbin, but there's no harm in doing it twice.
    Cpanel::Validate::VirtualUsername::validate_for_creation_or_die( $user . '@' . $domain );

    Cpanel::AdminBin::Call::call( 'Cpanel', 'ftp_call', 'SET_HOMEDIR', $user, $domain, $ftpdir );

    my $output = _create_homedir($ftpdir);
    $result->raw_message($output) if $output;

    return 1;
}

sub _create_homedir {
    my ($ftpdir) = @_;
    $ftpdir = "$Cpanel::homedir/" . $ftpdir;

    $ftpdir =~ s/\.\.//g;
    $ftpdir = Cpanel::SafeDir::safedir($ftpdir);

    my $output;

    # Note: perms are 0755 so apache can access the newly created
    # directory to serve files
    Cpanel::SafeDir::MK::safemkdir( $ftpdir, 0755 ) or $output = "Failed to mkdir: $ftpdir: $!";
    chmod 0755, $ftpdir;

    return $output;
}

#Parameters:
#
#   user    - the name (without domain) of the FTP account to create
#       - must pass Cpanel::Validate::VirtualUsername when combined with the domain
#       - whitespace is stripped
#       - if 'disallowdot' is passed, periods are stripped
#
#   pass    - the password to set for the new account#
#
#   domain  - The domain at which to create the FTP account. If not specified,
#             the cPanel user's primary domain will be used. This default behavior
#             is for backward compatibility with earlier versions of the API.
#
#   homedir  - (optional) the new FTP account's directory to set:
#       - defaults to $cphomedir/$user if not given
#       - whitespace and double-dots are stripped
#       - if q<>, directory will be $cphomedir/public_html
#       - otherwise, directory is $cphomedir/$ftpdir
#
sub add_ftp {
    my ( $args, $result ) = @_;
    my ( $user, $pass, $pass_hash, $domain, $ftpdir, $quota, $disallowdot ) = $args->get(qw(user pass pass_hash domain homedir quota disallowdot));

    $disallowdot = 1 unless defined $disallowdot;

    ## in reality, resetting $Cpanel::context is probably not needed
    $Cpanel::context = 'ftp';

    if ( !( length($pass) xor length($pass_hash) ) ) {
        $result->error('add_ftp: You must specify either a password or a password hash.');
        return;
    }
    elsif ( !length $user ) {
        $result->error('You must specify a user name.');
        return;
    }

    if ( !$quota || $quota =~ m/unlimited/i ) {
        $quota = 0;
    }
    elsif ( $quota !~ m/^\d+$/ ) {
        $result->error('The quota must be a number or “unlimited”.');
        return;
    }

    ( $user, $domain ) = _normalize_user_and_domain( $user, $domain );

    $user =~ s/\s//g;
    if ($disallowdot) { $user =~ s/[.]//g; }

    if ( defined $ftpdir ) {
        $ftpdir =~ s/\.\.//g;
    }
    elsif ( defined $domain ) {
        $ftpdir = $user . '@' . $domain;
    }
    else {
        $ftpdir = $user;
    }

    # This validation is also done by the adminbin, but there's no harm in doing it twice.
    Cpanel::Validate::VirtualUsername::validate_for_creation_or_die( $user . '@' . $domain );

    Cpanel::AdminBin::Call::call( 'Cpanel', 'ftp_call', 'CREATE_USER', $user, $domain, $pass, $ftpdir, $pass_hash );

    my $output = _create_homedir($ftpdir);
    $result->raw_message($output) if $output;

    my $set_quota = Cpanel::API::execute( "Ftp", "set_quota", { user => $user, domain => $domain, quota => $quota } );
    unless ( $set_quota->status() ) {
        $result->raw_error($_) for @{ $set_quota->errors() || [] };
        return;
    }

    return 1;
}

sub delete_ftp {
    my ( $args, $result ) = @_;
    my ( $user, $domain, $destroy ) = $args->get( 'user', 'domain', 'destroy' );

    ## in reality, resetting $Cpanel::context is probably not needed
    $Cpanel::context = 'ftp';

    if ( !length $user ) {
        $result->error('You must specify a user name.');
        return;
    }

    ( $user, $domain ) = _normalize_user_and_domain( $user, $domain );

    my $homedir;

    my $acct = _lookup_ftp_acct( $user, $domain );
    if ( !$acct ) {
        $result->error( 'The FTP account “[_1]” cannot be removed because it does not exist.', $user );
        return;
    }

    if ($destroy) {
        $homedir = $acct->{'homedir'};
    }

    my $adminbin_result = Cpanel::AdminBin::run_adminbin_with_status( 'ftp', 'DEL', $user, $domain );
    if ( !$adminbin_result->{'status'} ) {
        $result->raw_error( $adminbin_result->{'error'} );
        return;
    }

    if ($destroy) {
        if (   $homedir =~ /^($Cpanel::homedir|$Cpanel::abshomedir)\/[\w\-]+/
            && $homedir ne $Cpanel::homedir
            && $homedir ne $Cpanel::abshomedir
            && $homedir ne $Cpanel::homedir . '/public_html'
            && $homedir ne $Cpanel::abshomedir . '/public_html'
            && $homedir ne $Cpanel::homedir . '/public_ftp'
            && $homedir ne $Cpanel::abshomedir . '/public_ftp' ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Errors');
            my $output = Cpanel::SafeRun::Errors::saferunallerrors( 'rm', '-rfv', $homedir );
            $result->raw_message($output);
        }
    }

    my $set_quota = Cpanel::API::execute( "Ftp", "set_quota", { user => $user, domain => $domain, quota => 0, kill => 1 } );
    unless ( $set_quota->status() ) {
        $result->error('Failed to set deleted user quota to 0.');
        return;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::UserManager::Record');
    Cpanel::LoadModule::load_perl_module('Cpanel::UserManager::Storage');
    my $usermanager_obj = Cpanel::UserManager::Record->new(
        {
            username => $user,
            domain   => $domain,
            type     => 'service',
        }
    );

    # if there's not a subaccount, we're okay with that; it's just a legacy
    # account.
    if ($usermanager_obj) {

        # if the user exists, but there is no annotation (unlinked legacy)
        # then we're ok; this will not error. Deleting zero rows is still
        # a successful delete.
        my $delete_ok = Cpanel::UserManager::Storage::delete_annotation( $usermanager_obj, 'ftp' );
        if ( !$delete_ok ) {
            $result->error( 'The system failed to delete the annotation record for the ftp account “[_1]@[_2]”', $user, $domain );
            return;
        }
    }

    return 1;
}

sub passwd {
    my ( $args, $result ) = @_;
    my ( $user, $domain, $pass ) = $args->get( 'user', 'domain', 'pass' );

    if ( !( length($pass) ) ) {
        $result->error('You must specify a password.');
        return;
    }
    elsif ( !length $user ) {
        $result->error('You must specify a user name.');
        return;
    }

    ( $user, $domain ) = _normalize_user_and_domain( $user, $domain );

    $user =~ s!/!!g;

    ## in reality, resetting $Cpanel::context is probably not needed
    $Cpanel::context = 'ftp';

    Cpanel::AdminBin::Call::call( 'Cpanel', 'ftp_call', 'SET_PASSWORD', $user, $domain, $pass );

    return 1;
}

sub get_quota {
    my ( $args,    $result ) = @_;
    my ( $account, $domain ) = $args->get( 'account', 'domain' );

    if ( !$account ) {
        $result->error('You must specify an account.');
        return;
    }

    ( $account, $domain ) = _normalize_user_and_domain( $account, $domain );

    my $does_exist = _lookup_ftp_acct( $account, $domain );

    if ( !$does_exist ) {
        $result->error( 'The FTP account “[_1]” at domain “[_2]” does not exist.', $account, $domain );
        return;
    }

    if ( $account eq 'anonymous' ) { $account = 'ftp'; }
    my ($quota);
    my $ftplock = Cpanel::SafeFile::safeopen( \*FTPQUOTA, "<", "$Cpanel::homedir/etc/ftpquota" );
    unless ($ftplock) {
        Cpanel::Debug::log_warn("Could not read from $Cpanel::homedir/etc/ftpquota");
        $result->error( 'Could not read from [_1]', "$Cpanel::homedir/etc/ftpquota" );
        return;
    }
    Cpanel::LoadModule::load_perl_module('Cpanel::FtpUtils::Passwd');
    while ( defined( my $line = <FTPQUOTA> ) ) {
        if (
            Cpanel::FtpUtils::Passwd::line_matches_user(
                line       => $line,
                user       => $account,
                domain     => $domain,
                maindomain => $Cpanel::CPDATA{'DNS'}
            )
        ) {
            ( undef, $quota ) = split( /:/, $line );
        }
    }
    Cpanel::SafeFile::safeclose( \*FTPQUOTA, $ftplock );
    if ( !$quota ) {
        $result->data('unlimited');
    }
    else {
        $result->data( $quota / 1048576 );
    }
    return 1;
}

sub set_quota {
    my ( $args, $result ) = @_;
    my ( $user, $domain, $quota, $kill ) = $args->get(qw(user domain quota kill));

    if ( !length $user ) {
        $result->error('You must specify a user name.');
        return;
    }

    ( $user, $domain ) = _normalize_user_and_domain( $user, $domain );

    $user =~ s!/!!g;
    $quota = int( $quota || 0 );

    if ( $user eq 'anonymous' ) { $user = 'ftp'; }

    if ( !$kill && !ftp_exists( $args, $result ) ) {
        return;
    }

    my $added = 0;
    $quota = int( $quota * 1048576 );
    if ( $quota == 0 ) { $kill = 1; }
    if ( !-e "$Cpanel::homedir/etc" ) {
        mkdir "$Cpanel::homedir/etc", 0755;
    }
    if ( !-e $Cpanel::homedir . '/etc/ftpquota' ) {
        if ( open my $ftpquota_fh, '>>', $Cpanel::homedir . '/etc/ftpquota' ) {
            close $ftpquota_fh;
        }
        else {
            Cpanel::Debug::log_warn("Failed to create FTP quota file $Cpanel::homedir/etc/ftpquota: $!");
        }
    }
    my $ftplock = Cpanel::SafeFile::safeopen( \*FTPQUOTA, '+<', $Cpanel::homedir . '/etc/ftpquota' );
    if ( !$ftplock ) {
        my $msg = "Could not edit $Cpanel::homedir/etc/ftpquota";
        Cpanel::Debug::log_warn($msg);
        $result->error( "Could not edit [_1]", $Cpanel::homedir . '/etc/ftpquota' );
        return;
    }
    my @FTPL = <FTPQUOTA>;
    seek( FTPQUOTA, 0, 0 );

    my $full_username = $user . '@' . $domain;
    Cpanel::LoadModule::load_perl_module('Cpanel::FtpUtils::Passwd');
    foreach my $line (@FTPL) {
        if (
            Cpanel::FtpUtils::Passwd::line_matches_user(
                line       => $line,
                user       => $user,
                domain     => $domain,
                maindomain => $Cpanel::CPDATA{'DNS'}
            )
        ) {
            if ( !$kill ) {
                $added = 1;
                print FTPQUOTA $full_username . ':' . $quota . "\n";
            }
        }
        else {
            print FTPQUOTA $line;    # print existing line
        }
    }
    if ( !$added && !$kill ) {
        print FTPQUOTA $full_username . ':' . $quota . "\n";
    }
    truncate( FTPQUOTA, tell(FTPQUOTA) );
    Cpanel::SafeFile::safeclose( \*FTPQUOTA, $ftplock );

    if ( $user eq 'ftp' ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Errors');
        Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/bin/ftpwrap', 'QUOTA', '0', '0', '0' );
    }
    else {
        my $ftpdir;
        foreach my $facct ( _listftp() ) {
            next if $facct->{'type'} && $facct->{'type'} eq 'main';
            next if !$facct->{'user'} || $facct->{'user'} ne $full_username;
            $ftpdir = $facct->{'homedir'};
            last;
        }

        if ($ftpdir) {
            if ( Cpanel::FtpUtils::Server::ftp_daemon_info()->{'name'} eq 'pure-ftpd' ) {
                my ( $results, $retcode ) = _pure_quotacheck($ftpdir);

                if ( $retcode != 0 ) {

                    # (Note: The "~[" usage below accounts for a literal "[" in bracket notation.)
                    $result->error( "Error detected with pure-quotacheck for [_1] ~[[_2]~]: [_3]", $user, $ftpdir, $results );
                    return;
                }
            }
        }
        elsif ( !$kill ) {    # account must have already been removed
            Cpanel::Debug::log_warn("Failed to determine FTP account $user directory.");
            $result->error( "Failed to determine FTP account [_1] directory.", $user );
            return;
        }

    }
    return 1;
}

sub _pure_quotacheck {
    my (@args) = @_;
    my ( $results, $retcode );

    my $bin;
    if ( -x '/usr/sbin/pure-quotacheck' ) {
        $bin = '/usr/sbin/pure-quotacheck';
    }
    elsif ( -x '/usr/local/sbin/pure-quotacheck' ) {
        $bin = '/usr/local/sbin/pure-quotacheck';
    }
    else {
        return ( "pure-quotacheck does not exist", 1 );
    }
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Object');
    my $run = Cpanel::SafeRun::Object->new( 'program' => $bin, 'args' => [ '-d', @args ] );
    $results = $run->stdout() . $run->stderr();
    $retcode = $run->CHILD_ERROR() >> 8;
    return ( $results, $retcode );
}

sub list_sessions {
    ## no args
    my ( $args, $result ) = @_;

    my ( $pid, $loginat, $cmdline );
    my (%FTP);

    my $PS   = _list_sessions_ps();
    my $pure = 0;
    foreach my $ps (@$PS) {
        ( undef, $pid, undef, undef, undef, undef, undef, undef, $loginat, undef, $cmdline ) = split( /[\s\t]+/, $ps, 11 );
        if ( $cmdline =~ /^\s*proftpd:/ ) {
            my ( $proc, $userhost, $status ) = split( /:/, $cmdline );
            $status =~ s/\s//g;
            my ( $user, $host ) = split( /\s+-\s+/, $userhost );
            $user =~ s/\s//g;
            $host =~ s/\s//g if defined $host;
            $FTP{$pid}{'user'}   = $user;
            $FTP{$pid}{'host'}   = $host;
            $FTP{$pid}{'status'} = $status;
        }
        else {
            my ( $proc, $status ) = split( /\s+/, $cmdline );
            $status =~ s/[\(\)]//g;
            $FTP{$pid}{'status'} = $status;
            $pure = 1;
        }

        $FTP{$pid}{'pid'}     = $pid;
        $FTP{$pid}{'login'}   = $loginat;
        $FTP{$pid}{'cmdline'} = $cmdline;
    }

    if ($pure) {
        my $now  = time();
        my $aref = Cpanel::AdminBin::adminfetch( 'ftp', 0, 'SESSIONS', 'storeable', '0', '0' );
        if ( ref $aref eq 'ARRAY' ) {
            foreach my $opt ( @{$aref} ) {
                $FTP{ $opt->{'pid'} }{'pid'}    = $opt->{'pid'};
                $FTP{ $opt->{'pid'} }{'user'}   = $opt->{'user'};
                $FTP{ $opt->{'pid'} }{'login'}  = localtime( $now - $opt->{'time'} );
                $FTP{ $opt->{'pid'} }{'status'} = $opt->{'state'};
                $FTP{ $opt->{'pid'} }{'host'}   = $opt->{'host'};
                $FTP{ $opt->{'pid'} }{'file'}   = $opt->{'file'};
            }
        }
    }

    my @RSD;
    foreach my $pid ( sort keys %FTP ) {
        push @RSD, $FTP{$pid};
    }

    $result->data( \@RSD );
    return 1;
}

## extracted to facilitate testing/mocking
sub _list_sessions_ps {
    my $ps = `ps -U$Cpanel::user,$> uwwwww`;
    my @PS = split( /\n/, $ps );

    # When a username is too long (typically greater than 8 chars),
    # Then ps uses the uid instead of the username in the output.
    # Therefore, we check for either the cpanel username or the
    # effective uid in the output.
    @PS = grep( /^.*(proftpd|pure-ftpd)/, @PS );
    return \@PS;
}

sub kill_session {
    my ( $args, $result ) = @_;
    my ($login) = $args->get('login') || 'all';

    my @pid_list;

    if ( $login eq 'all' ) {
        my $result = Cpanel::API::execute( "Ftp", "list_sessions" );
        my $AoH    = $result->data();
        @pid_list = map { $_->{pid} } @$AoH;
    }
    elsif ( $login =~ /^\d+$/ && $login && $login > 0 ) {
        push @pid_list, $login;
    }

    foreach my $pid (@pid_list) {
        _kill_session_syscalls($pid);
        Cpanel::AdminBin::adminrun( 'ftp', 'KILLSESSION', $pid, 0 );
    }

    return 1;
}

## extracted for unit testing reasons
sub _kill_session_syscalls {
    my ($pid) = @_;
    kill 'TERM', $pid;
    sleep 1;
    kill 'KILL', $pid;
    return;
}

sub get_welcome_message {
    ## no args
    my ( $args, $result ) = @_;
    my $message = '';
    if ( sysopen( my $msg_fh, _get_welcome_message_fname(), Cpanel::Fcntl::or_flags(qw( O_RDONLY O_NOFOLLOW )), ) ) {
        while ( my $line = readline $msg_fh ) {
            $message .= $line;
        }
        close $msg_fh;
    }
    $result->data($message);
    return 1;
}

sub set_welcome_message {
    my ( $args, $result ) = @_;
    my ($message) = $args->get('message');

    if ( !defined $message ) {
        $result->error('You must specify a message.');
        return;
    }

    my $fname = _get_welcome_message_fname();
    if ( sysopen( my $msg_fh, _get_welcome_message_fname(), Cpanel::Fcntl::or_flags(qw( O_WRONLY O_TRUNC O_CREAT O_NOFOLLOW )), 0644 ) ) {
        print {$msg_fh} $message;
        close $msg_fh;
        return 1;
    }
    else {
        $result->error( "Could not edit [_1]: [_2]", $fname, $! );
        return;
    }

}

## extracted for unit test purposes
sub _get_welcome_message_fname {
    return $Cpanel::homedir . '/public_ftp/welcome.msg';
}

sub server_name {
    ## no args
    my ( $args, $result ) = @_;
    if ( Cpanel::FtpUtils::Server::determine_server_type() eq 'pure-ftpd' ) {
        $result->data('pure-ftpd');
    }
    elsif ( Cpanel::FtpUtils::Server::determine_server_type() eq 'proftpd' ) {
        $result->data('proftpd');
    }
    else {
        $result->data('disabled');
    }

    return 1;
}

=head2 Ftp::get_ftp_daemon_info

Get extended information about the currently configured FTP server.

=head3 Arguments

n/a

=head3 Returns

A hash containing:

  - name - String - 'pure-ftpd', 'proftpd', or ''. This will be '' when enabled is 0.
  - enabled - Boolean - 0 or 1
  - supports - Hash - Features the daemon supports
      - quota - Boolean - 0 or 1
      - login_without_domain - Boolean - 0 or 1

=cut

sub get_ftp_daemon_info {
    my ( $args, $result ) = @_;
    my $info = Cpanel::FtpUtils::Server::ftp_daemon_info();
    $result->data($info);
    return 1;
}

##################################################
## ANONYMOUS FTP

sub allows_anonymous_ftp {
    ## no args
    my ( $args, $result ) = @_;
    if ( !-e "$Cpanel::homedir/public_ftp" ) {
        if ( $Cpanel::CPDATA{'DEMO'} ne '1' ) {    # Don't create directory in DEMO mode
            mkdir "$Cpanel::homedir/public_ftp", 0700;
        }

        # not other writeable
        $result->data( { allows => 0 } );
        return;
    }

    # Equal to '5' when read&exec for other, otherwise equal to '0'
    my $is_other_read_exec = ( stat( $Cpanel::homedir . '/public_ftp' ) )[2] & 00005;
    $result->data( { allows => int( !!$is_other_read_exec ) } );
    return 1;
}

sub allows_anonymous_ftp_incoming {
    ## no args
    my ( $args, $result ) = @_;
    if ( !-e "$Cpanel::homedir/public_ftp/incoming" ) {
        if ( $Cpanel::CPDATA{'DEMO'} ne '1' ) {    # Don't create directory in DEMO mode
            mkdir "$Cpanel::homedir/public_ftp/incoming", 0700;
        }

        # not other writeable
        $result->data( { allows => 0 } );
        return;
    }

    # Equal to '2' when writeable, otherwise equal to '0'
    my $is_other_write = ( stat( $Cpanel::homedir . '/public_ftp/incoming' ) )[2] & 00002;
    $result->data( { allows => int( !!$is_other_write ) } );
    return 1;
}

sub set_anonymous_ftp {
    my ( $args, $result ) = @_;
    my ($set) = $args->get('set') || 0;

    if ( int($set) == 1 ) {
        chmod 0755, "$Cpanel::homedir/public_ftp";
    }
    else {
        chmod 0750, "$Cpanel::homedir/public_ftp";
    }
    return 1;
}

sub set_anonymous_ftp_incoming {
    my ( $args, $result ) = @_;
    my ($set) = $args->get('set') || 0;

    if ( !-e "$Cpanel::homedir/public_ftp/incoming" ) {
        if ( int($set) == 1 ) {
            mkdir "$Cpanel::homedir/public_ftp/incoming", 0753;
        }
        else {
            mkdir "$Cpanel::homedir/public_ftp/incoming", 0700;
        }
    }
    else {
        if ( int($set) == 1 ) {
            chmod 0753, "$Cpanel::homedir/public_ftp/incoming";
        }
        else {
            chmod 0700, "$Cpanel::homedir/public_ftp/incoming";
        }
    }
    return 1;
}

sub get_port {
    my ( $args, $result ) = @_;
    my $port = Cpanel::AdminBin::Call::call( 'Cpanel', 'ftp_call', 'GET_PORT' );
    $result->data( { port => $port || 21 } );
    return 1;
}

##################################################
## UTILITY FUNCTIONS (NON-API FUNCTIONS)
## functions moved from Cpanel::Ftp in order to reduce the binary size of uapi.pl

sub _fullftplist {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my $ftpaccts_ref = _listftp();
    my %ACCTS        = map {
        $_->{'user'} => {
            'dir'    => $_->{'homedir'},
            'type'   => $_->{'type'},
            'reldir' => _getreldir_from_dir( $_->{'homedir'} ),
            'quota'  => 0,
        }
    } @$ftpaccts_ref;

    if ( !%ACCTS ) {
        return wantarray ? %ACCTS : \%ACCTS;
    }

    my %SEENFTP;
    if ( !-e "$Cpanel::homedir/etc/ftpquota" ) {
        Cpanel::FileUtils::TouchFile::touchfile("$Cpanel::homedir/etc/ftpquota");
    }
    my $ftplock = eval { Cpanel::SafeFile::safeopen( \*FTPQUOTA, '<', $Cpanel::homedir . '/etc/ftpquota' ); };
    if ($ftplock) {
        while ( readline( \*FTPQUOTA ) ) {
            chomp();
            my ( $acct, $quota ) = split( /:/, $_ );

            if ( $acct !~ tr/@// ) {    # pre-11.54 compatibility
                $acct .= '@' . $Cpanel::CPDATA{'DNS'};
            }

            next if exists $SEENFTP{$acct} || !exists $ACCTS{$acct};
            $ACCTS{$acct}{'quota'} = int $quota;
            $SEENFTP{$acct} = 1;
        }
        Cpanel::SafeFile::safeclose( \*FTPQUOTA, $ftplock );
    }
    else {
        # Even if we couldn't read the FTP quota info (example: couldn't acquire the lock
        # because the cPanel account itself is over quota), it still makes sense to proceed on
        # with gathering the FTP account list. Just log the problem.
        Cpanel::Debug::log_warn("Could not acquire a lock on $Cpanel::homedir/etc/ftpquota");
    }

    if ( !-e '/var/cpanel/noanonftp' && $ACCTS{'ftp'} ) {
        $ACCTS{'anonymous'}{'quota'} = $ACCTS{'ftp'}{'quota'};
    }
    else {
        delete $ACCTS{'anonymous'};
        delete $ACCTS{'ftp'};
    }

    my ( $mainacct_used, $mainacct_quota ) = Cpanel::Quota::displayquota();
    $mainacct_used  = 0 if !$mainacct_used  || $mainacct_used eq $Cpanel::Quota::QUOTA_NOT_ENABLED_STRING;
    $mainacct_quota = 0 if !$mainacct_quota || $mainacct_quota eq $Cpanel::Quota::QUOTA_NOT_ENABLED_STRING;
    $mainacct_used  *= 1024**2;
    $mainacct_quota *= 1024**2;

    my $_ftpservername = Cpanel::API::execute( 'Ftp', 'server_name' )->data();
    foreach my $acct ( keys %ACCTS ) {
        my $used = 0;
        my $dir  = $ACCTS{$acct}{'dir'};
        if ( $acct eq $Cpanel::user || $acct eq $Cpanel::user . '_logs' ) {
            $used = $mainacct_used;
            $ACCTS{$acct}{'quota'} = $mainacct_quota;
        }
        else {
            if ( defined $dir && open my $ftpquota_fh, '<', "$dir/.ftpquota" ) {
                my $quotaline = <$ftpquota_fh> || '';
                chomp $quotaline;
                $used = ( split( /\s+/, $quotaline ) )[1];
                close $ftpquota_fh;
            }
        }

        if (
               $acct ne $Cpanel::user . '_logs'
            && $acct ne $Cpanel::user
            && $acct !~ /\@/
            && (
                $_ftpservername eq 'pure-ftpd'    # FIXME: See LC-2595
                || !Cpanel::ExpVar::Utils::hasdedicatedip()
            )
        ) {
            $ACCTS{$acct}{'serverlogin'} = $acct . '@' . $Cpanel::CPDATA{'DNS'};
        }
        else {
            $ACCTS{$acct}{'serverlogin'} = $acct;
        }

        #Because we return the “ftp” and “anonymous” users as such, without
        #domains, but we store the quota for that account as “ftp\@$domain”,
        #we need to grab that quota figure and put it on these accounts, or else
        #some themes (e.g., Paper Lantern as in v54) will incorrectly show an
        #unlimited quota for that account.
        my $anonuser = "ftp\@$Cpanel::CPDATA{'DNS'}";
        if ( ( $acct eq 'ftp' || $acct eq 'anonymous' ) && exists $ACCTS{$anonuser} ) {
            $ACCTS{$acct}{'quota'} = $ACCTS{$anonuser}{'quota'};
        }

        $ACCTS{$acct}{'used'}    = $used;
        $ACCTS{$acct}{'megused'} = Cpanel::Math::floatto( ( $used / 1048576 ), 2 );
        if ( int( $ACCTS{$acct}{'quota'} ) == 0 ) {
            $ACCTS{$acct}{'megquota'}   = 0;
            $ACCTS{$acct}{'percent'}    = 0;
            $ACCTS{$acct}{'barlength'}  = 0;
            $ACCTS{$acct}{'wbarlength'} = 0;
        }
        else {
            my $percent   = ( $used / $ACCTS{$acct}{'quota'} );
            my $barlength = Cpanel::Math::ceil( $percent * 200 );
            if ( $barlength > 200 ) { $barlength = 200; }
            my $wbarlength = ( 200 - $barlength );
            $ACCTS{$acct}{'megquota'}   = Cpanel::Math::floatto( ( $ACCTS{$acct}{'quota'} / 1048576 ), 2 );
            $ACCTS{$acct}{'percent'}    = Cpanel::Math::ceil( $percent * 100 );
            $ACCTS{$acct}{'barlength'}  = $barlength;
            $ACCTS{$acct}{'wbarlength'} = $wbarlength;
        }
    }

    return wantarray ? %ACCTS : \%ACCTS;
}

sub _listftp {

    # Pass some dummy arguments in the username/domain/password slots
    # since LISTSTORE doesn't operate on a per-user basis.
    my $aref = Cpanel::AdminBin::adminfetch(
        'ftp', "$Cpanel::ConfigFiles::FTP_PASSWD_DIR/$Cpanel::user", 'LISTSTORE', 'storeable',
        '0',   '0', '0'
    );

    $aref = []           if ( !$aref );
    $aref = [ (%$aref) ] if ( ref($aref) eq 'HASH' );

    return wantarray ? @{$aref} : $aref;
}

sub _getreldir_from_dir {
    my $homedir = shift;
    $homedir =~ s/^$Cpanel::homedir//g;
    $homedir =~ s/^$Cpanel::abshomedir//g;
    $homedir =~ s/\.\.//g;
    $homedir =~ s/^\///g;
    return $homedir;
}

sub _countftp {
    my @ftpaccts = _listftp();
    my $ftpcount = 0;
    foreach my $acct (@ftpaccts) {
        if ( $acct->{'type'} eq 'sub' ) {
            $ftpcount++;
        }
    }
    if ( $ftpcount eq '' ) { return 0; }
    return $ftpcount;
}

sub _lookup_ftp_acct {
    my ( $user, $domain ) = @_;

    my @ftpaccts    = _listftp();
    my $looking_for = $user . '@' . $domain;

    foreach my $acct (@ftpaccts) {
        if ( $acct->{'user'} eq $looking_for ) {
            return $acct;
        }
    }
    return;
}

sub _normalize_user_and_domain {
    my ( $user, $domain ) = @_;
    if ( $user =~ tr/@// ) {
        if ($domain) {
            die "You may not specify a domain both in the user field and in the domain field.\n";
        }
        ( $user, $domain ) = split /\@/, $user;
    }

    # For backward compatibility with previous versions of the API, where all FTP
    # accounts used the cPanel account's primary domain.
    if ( !$domain ) {
        $domain = $Cpanel::CPDATA{'DNS'} || die 'Primary account domain unknown';
    }

    return ( $user, $domain );
}

1;
