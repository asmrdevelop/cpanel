#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/ftp_call.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::ftp_call;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Carp      ();
use Cpanel::Exception ();

my @reserved_usernames = qw(
  anonymous
  ftp
);

my $PASSWORD_INDEX_IN_ETC_PASSWD = 1;

#----------------------------------------------------------------------

# XXX Please don’t add to this list.
use constant _actions__pass_exception => (
    'CREATE_USER',
    'LOOKUP_PASSWORD_HASH',
    'SET_PASSWORD',
    'SET_HOMEDIR',
    'GET_PORT',
);

# Add to this list instead.
use constant _actions => (
    _actions__pass_exception(),
);

#Override to allow execution of resetpass.cgi during password changes
use constant _allowed_parents => (
    __PACKAGE__->SUPER::_allowed_parents(),
    '/usr/local/cpanel/base/resetpass.cgi',
);

sub _init {
    my ($self) = @_;

    # This prevents HTML from being included in error messages that get handled by the locale system.
    # Since more and more of the messages are being sent over the API and then HTML-encoded upon receipt
    # by the client (as it should), including HTML in the message won't be helpful.
    local $Cpanel::Carp::OUTPUT_FORMAT = 'xml';

    $self->cpuser_has_feature_or_die('ftpaccts');

    return;
}

sub _demo_actions {
    return ('GET_PORT');
}

sub SET_HOMEDIR {
    my ( $self, $ftpuser, $ftpdomain, $ftpdir ) = @_;

    $self->_verify_ownership_or_die($ftpdomain);

    my $full_username = $ftpuser . '@' . $ftpdomain;
    require Cpanel::Validate::VirtualUsername;
    Cpanel::Validate::VirtualUsername::validate_for_creation_or_die($full_username);

    my $homedir = $self->get_cpuser_homedir();

    if ( !length $ftpdir ) {
        $ftpdir = $homedir;
    }
    else {
        $ftpdir =~ s<\A/+><>;

        #Prefix with a / to get validate_or_die() to blow up if a recursor
        #(e.g., "../..") is passed in.
        require Cpanel::Validate::FilesystemPath;
        Cpanel::Validate::FilesystemPath::validate_or_die("/$ftpdir");

        $ftpdir = "$homedir/$ftpdir";
    }

    require Cwd;
    my $abshome = Cwd::abs_path($homedir);
    require Cpanel::SafeDir;
    $ftpdir = Cpanel::SafeDir::safedir( $ftpdir, $homedir, $abshome );

    require Cpanel::Transaction::File::Raw;
    my $trans = Cpanel::Transaction::File::Raw->new( path => $self->_ftp_pw_file() );

    my $ftp_passwd_sr = $trans->get_data();

    my $found = 0;
    my $iterator;
    require Cpanel::StringFunc::LineIterator;
    Cpanel::StringFunc::LineIterator->new(
        $$ftp_passwd_sr,
        sub {
            my $line = $_;
            return if $line !~ /^\Q${full_username}\E:/;

            $iterator ||= shift;
            my @parts = split ':', $line;
            $parts[5] = $ftpdir;
            $iterator->replace_with( join( ':', @parts ) );
            $found = 1;
        }
    );

    if ($iterator) {
        $trans->set_first_modified_offset( $iterator->get_first_modified_offset() );
    }

    if ( !$found ) {
        die Cpanel::Exception->create_raw("User ${full_username} not found.");
    }

    my ( $ok, $err ) = $trans->save_and_close();
    die Cpanel::Exception->create_raw($err) if !$ok;

    $self->_ftpupdate();

    return;

}

#$ftpdir is relative to the user's homedir.
sub CREATE_USER {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $self, $ftpuser, $ftpdomain, $ftppass, $ftpdir, $ftpcpass ) = @_;

    $self->_verify_ownership_or_die($ftpdomain);

    my $cpusername = $self->get_caller_username();

    my $full_username = $ftpuser . '@' . $ftpdomain;

    require Cpanel::Validate::VirtualUsername;
    Cpanel::Validate::VirtualUsername::validate_for_creation_or_die($full_username);

    if ( grep { $_ eq lc $ftpuser } @reserved_usernames ) {
        die Cpanel::Exception->create( 'The following usernames are reserved for anonymous [output,abbr,FTP,File Transfer Protocol] access and cannot be used for new accounts: [join,~, ,_1]', [ \@reserved_usernames ] );
    }

    if ( length $ftppass ) {
        require Cpanel::PasswdStrength::Check;
        Cpanel::PasswdStrength::Check::verify_or_die( app => 'ftp', pw => $ftppass );
    }
    elsif ( length $ftpcpass ) {

        # Protect agains invalid data (colon, newline, etc.) intentionally being provided in order to manipulate
        # unrelated parts of the file. This is the same check that's used by the transfer system for FTP password
        # file entries.
        require Cpanel::Validate::PwFileEntry;
        Cpanel::Validate::PwFileEntry::validate_or_die($ftpcpass);

        # Protect against cleartext password accidentally being provided and stored in this field, and also provide
        # redundant check against other invalid data being intentionally stored.
        $ftpcpass =~ m{^\$[0-9]\$[a-zA-Z0-9./\$]+$} or die Cpanel::Exception->create('The system received an invalid password hash.');
    }
    else {
        die 'ftp_call: ' . Cpanel::Exception->create('You must specify a password or a password hash.');
    }

    my $homedir = $self->get_cpuser_homedir();

    if ( !length $ftpdir ) {
        $ftpdir = $homedir;
    }
    else {
        $ftpdir =~ s<\A/+><>;

        #Prefix with a / to get validate_or_die() to blow up if a recursor
        #(e.g., "../..") is passed in.
        require Cpanel::Validate::FilesystemPath;
        Cpanel::Validate::FilesystemPath::validate_or_die("/$ftpdir");

        $ftpdir = "$homedir/$ftpdir";
    }

    require Cwd;
    my $abshome = Cwd::abs_path($homedir);
    require Cpanel::SafeDir;
    $ftpdir = Cpanel::SafeDir::safedir( $ftpdir, $homedir, $abshome );

    require Cpanel::Auth::Generate;
    $ftpcpass = $ftppass ? Cpanel::Auth::Generate::generate_password_hash($ftppass) : $ftpcpass;

    require Cpanel::Config::LoadCpUserFile;
    my $maxftp = Cpanel::Config::LoadCpUserFile::load( $self->get_caller_username() )->{'MAXFTP'};

    if ( defined $maxftp && $maxftp =~ m/^\s*0+$/ ) {
        die Cpanel::Exception->create( 'You have already used your maximum allotment ([numf,_1]) of [output,abbr,FTP,File Transfer Protocol] accounts.', [$maxftp] );
    }

    if ( defined $maxftp && ( $maxftp eq '' or $maxftp eq 'unlimited' ) ) {
        $maxftp = undef;
    }

    require Cpanel::Transaction::File::Raw;
    my $trans = Cpanel::Transaction::File::Raw->new( path => $self->_ftp_pw_file() );

    my $ftp_passwd_sr = $trans->get_data();

    require Cpanel::StringFunc::Match;
    require Cpanel::StringFunc::LineIterator;
    my $iterator;
    my $count = 0;
    Cpanel::StringFunc::LineIterator->new(
        $$ftp_passwd_sr,
        sub {
            my $line = $_;

            #ensure we don't go over quota
            if ( $self->_ARG_is_an_ftp_user_that_counts_against_MAXFTP() ) {
                $count++;

                if ( defined($maxftp) && $count >= $maxftp ) {
                    die Cpanel::Exception->create( 'You have already used your maximum allotment ([numf,_1]) of [output,abbr,FTP,File Transfer Protocol] accounts.', [$maxftp] );
                }
            }

            my $maindomain = $self->get_cpuser_domain;
            if ( ( $ftpdomain eq $maindomain && $line =~ m<\A\Q$ftpuser\E:>i ) || $line =~ m<\A\Q$ftpuser\E\@\Q$ftpdomain\E:>i ) {
                die Cpanel::Exception::create( 'NameConflict', 'The [output,abbr,FTP,File Transfer Protocol] user “[_1]” at the domain “[_2]” already exists.', [ $ftpuser, $ftpdomain ] );
            }

            {
                #If one of these matches, remove the line.
                #We replace these below.
                last if Cpanel::StringFunc::Match::beginmatch( $line, "$cpusername:" );
                last if Cpanel::StringFunc::Match::beginmatch( $line, 'ftp:' );

                return;
            }

            $iterator ||= shift;
            $iterator->replace_with(q<>);
        },
    );

    if ($iterator) {
        $trans->set_first_modified_offset( $iterator->get_first_modified_offset() );
    }

    my ( $cpuid, $cupass, $cpgid, $pwhome ) = ( getpwnam $cpusername )[ 2, 1, 3, 7 ];

    #Insert these lines at the end:
    $trans->substr(
        length $$ftp_passwd_sr,
        0,
        join(
            q<>,
            map { "$_\n" } (
                "$cpusername:${cupass}:${cpuid}:${cpgid}::$homedir:/bin/ftpsh",
                $self->_get_system_ftp_user_pw_line(),
                "${full_username}:${ftpcpass}:${cpuid}:${cpgid}:${cpusername}:${ftpdir}:/bin/ftpsh",
            )
        ),
    );

    my ( $ok, $err ) = $trans->save_and_close();
    die Cpanel::Exception->create_raw($err) if !$ok;

    $self->_ftpupdate();

    return;
}

sub GET_PORT {
    require Cpanel::FtpUtils::Config;
    if ( my $cfg = Cpanel::FtpUtils::Config->new() ) {
        return $cfg->get_port();
    }
    return 21;

}

sub SET_PASSWORD {
    my ( $self, $ftpuser, $ftpdomain, $ftppass ) = @_;

    $self->_verify_ownership_or_die($ftpdomain);

    my $full_username = $ftpuser . '@' . $ftpdomain;
    require Cpanel::Validate::VirtualUsername;
    Cpanel::Validate::VirtualUsername::validate_or_die($full_username);

    if ( !length $ftppass ) {
        die Cpanel::Exception->create('Submit a new password for the FTP user.');
    }

    require Cpanel::PasswdStrength::Check;
    Cpanel::PasswdStrength::Check::verify_or_die( app => 'ftp', pw => $ftppass );

    if ( !-e $self->_ftp_pw_file() ) {
        die Cpanel::Exception->create('You do not have any [output,abbr,FTP,File Transfer Protocol] accounts.');
    }

    require Cpanel::Transaction::File::Raw;
    my $trans = Cpanel::Transaction::File::Raw->new(
        path => $self->_ftp_pw_file(),
    );

    my $ftp_passwd_sr = $trans->get_data();

    require Cpanel::Auth::Generate;
    my $cryptftppass = Cpanel::Auth::Generate::generate_password_hash($ftppass);

    require Cpanel::FtpUtils::Passwd;
    require Cpanel::StringFunc::LineIterator;
    my ($iterator);
    my $main_domain = $self->get_cpuser_domain;
    Cpanel::StringFunc::LineIterator->new(
        $$ftp_passwd_sr,
        sub {
            my $line = $_;
            return if !Cpanel::FtpUtils::Passwd::line_matches_user( line => $line, user => $ftpuser, domain => $ftpdomain, maindomain => $main_domain );

            $iterator = shift;

            #This doesn't need to be anchored since what comes after the first
            #colon is the encrypted password.
            $line =~ s<:[^:]+><:$cryptftppass>;

            $iterator->replace_with($line);
            $iterator->stop();
        },
    );

    if ( !$iterator ) {
        die Cpanel::Exception->create( 'You do not have an [output,abbr,FTP,File Transfer Protocol] user named “[_1]”.', [$ftpuser] );
    }

    $trans->set_first_modified_offset( $iterator->get_first_modified_offset() );

    my ( $ok, $err ) = $trans->save_and_close();
    die Cpanel::Exception->create_raw($err) if !$ok;

    $self->_ftpupdate();

    return;
}

sub LOOKUP_PASSWORD_HASH {
    my ( $self, $ftpuser, $ftpdomain ) = @_;

    $self->_verify_ownership_or_die($ftpdomain);

    require Cpanel::Transaction::File::Raw;
    my $trans = Cpanel::Transaction::File::Raw->new(
        path => $self->_ftp_pw_file(),
    );

    my $ftp_passwd_sr = $trans->get_data();

    my $main_domain = $self->get_cpuser_domain;
    my $result;
    require Cpanel::StringFunc::LineIterator;
    require Cpanel::FtpUtils::Passwd;
    Cpanel::StringFunc::LineIterator->new(
        $$ftp_passwd_sr,
        sub {
            my $line = $_;
            return if !Cpanel::FtpUtils::Passwd::line_matches_user( line => $line, user => $ftpuser, domain => $ftpdomain, maindomain => $main_domain );

            $result = ( split /:/, $line )[1];

            my $iterator = shift;
            $iterator->stop();
        }
    );

    return $result;
}

#----------------------------------------------------------------------

sub _ftp_pw_file {
    my ($self) = @_;

    require Cpanel::ConfigFiles;
    return "$Cpanel::ConfigFiles::FTP_PASSWD_DIR/" . $self->get_caller_username();
}

#For speed, this reads $_ (i.e., $ARG in English.pm).
sub _ARG_is_an_ftp_user_that_counts_against_MAXFTP {
    my ($self) = @_;

    my ($user) = m<\A([^:]+)>;
    return 0 if !$user;
    return 0 if $user =~ m<_logs\z>;
    return 0 if $user eq $self->get_caller_username();

    return !( grep { $_ eq $user } @reserved_usernames ) ? 1 : 0;
}

sub _get_cpuser_password_hash {
    my ($self) = @_;

    my $user = $self->get_caller_username();

    require Cpanel::PwCache;
    return ( Cpanel::PwCache::getpwnam($user) )[1];
}

sub _get_system_ftp_user_pw_line {
    my ($self) = @_;

    require Cpanel::PwCache;
    my @pw_entry = Cpanel::PwCache::getpwnam('ftp');

    #TODO: This logic might be more generally useful .. ?
    return @pw_entry ? join( ':', @pw_entry[ 0 .. 3, 6 .. 8 ] ) : ();
}

sub _ftpupdate {
    my ($self) = @_;

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 10, "ftpupdate" );

    return;
}

sub _verify_ownership_or_die {
    my ( $self, $domain ) = @_;
    require Cpanel::AcctUtils::DomainOwner;
    if ( !Cpanel::AcctUtils::DomainOwner::is_domain_owned_by( $domain, $self->get_caller_username ) ) {
        die Cpanel::Exception::create( 'DomainOwnership', 'You do not own the domain “[_1]”.', [$domain] );
    }
    return 1;
}

1;
