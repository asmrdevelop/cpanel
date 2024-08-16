package Cpanel::WebDisk;

# cpanel - Cpanel/WebDisk.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use IO::Handle                  ();
use Cpanel::UserManager::Record ();
use Cpanel                      ();

use Cpanel::Fcntl::Constants          ();
use Cpanel::AdminBin                  ();
use Cpanel::Auth::Digest::Realm       ();
use Cpanel::Auth::Generate            ();
use Cpanel::Config::Httpd::IpPort     ();
use Cpanel::Exception                 ();
use Cpanel::Locale                    ();
use Cpanel::Logger                    ();
use Cpanel::LoadModule                ();
use Cpanel::PasswdStrength::Check     ();
use Cpanel::ProxyUtils                ();
use Cpanel::PwCache                   ();
use Cpanel::Rand::Get                 ();
use Cpanel::SafeDir                   ();
use Cpanel::SafeDir::MK               ();
use Cpanel::SafeFile                  ();
use Cpanel::UserManager::Storage      ();
use Cpanel::Validate::VirtualUsername ();

my $logger;
my $locale;

our $VERSION = '1.8';

sub WebDisk_init { }

sub _md5_hex {
    Cpanel::LoadModule::load_perl_module('Digest::MD5');
    return Digest::MD5::md5_hex(@_);
}

# The timestamp for an updated shadow entry (days since the epoch).
sub _shadow_time {
    return int( time() / ( 60 * 60 * 24 ) );
}

sub api2_passwdwebdisk {
    my %OPTS = @_;

    my $login    = $OPTS{'login'};
    my $password = $OPTS{'password'};
    $login    = '' unless defined $login;
    $password = '' unless defined $password;
    my $enabledigest =
      exists $OPTS{'digestauth'}
      ? $OPTS{'digestauth'}
      : $OPTS{'enabledigest'};
    $locale ||= Cpanel::Locale->get_handle();

    ## PASSWORD AUDIT (complete): cp's webdisk. $password is not encoded
    ##  modify=none to ensure passwords like '&a1x2)W7r3L1' work

    $login =~ s/[\+\r\n\s\t]//g;

    # we do not need to remove the user before having checked if the password is ok...
    if ( !_userexists($login) ) {
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'Unable to change password; user “[_1]” does not exist.', $login );
        return;
    }

    my $app = 'webdisk';
    if ( !Cpanel::PasswdStrength::Check::check_password_strength( 'pw' => $password, 'app' => $app ) ) {
        my $required_strength = Cpanel::PasswdStrength::Check::get_required_strength($app);
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'Sorry, the password you selected cannot be used because it is too weak and would be too easy to guess. Please select a password with strength rating of [numf,_1] or higher.', $required_strength );
        my $msg = $Cpanel::CPERROR{ $Cpanel::context // '' } // '';
        print STDERR "$msg\n";
        print "$msg\n";
        return;
    }

    my $cpass;
    if ( $password eq '*' ) {
        $cpass = '*';
    }
    else {
        while ( !$cpass || $cpass =~ /:/ ) {
            $cpass = Cpanel::Auth::Generate::generate_password_hash($password);
        }
    }

    # Race condition possible with multiple calls to api2_passwdwebdisk + api2_delwebdisk
    #   the lock should be shared
    if ( !_deluser( $login, 1 ) ) {
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'Unable to change password; user “[_1]” does not exist.', $login );
        return;
    }

    my $shadow_fh = IO::Handle->new();

    # TODO: switch to Cpanel::Transaction::File::Raw
    _safe_create_file( $Cpanel::homedir . '/etc/webdav/shadow' );    # make sure we have a 0600 file in place
    my $slock = Cpanel::SafeFile::safeopen( $shadow_fh, '>>', $Cpanel::homedir . '/etc/webdav/shadow' );
    if ( !$slock ) {
        $logger ||= Cpanel::Logger->new();
        $logger->warn("Could not append to $Cpanel::homedir/etc/webdav/shadow");
        return;
    }
    chmod( 0600, $Cpanel::homedir . '/etc/webdav/shadow' );
    my $realm      = Cpanel::Auth::Digest::Realm::get_realm();
    my $passwdtime = _shadow_time();
    print $shadow_fh "${login}:${cpass}:${passwdtime}::::::" . ( $enabledigest ? _md5_hex("$login:$realm:$password") : '' ) . "\n";
    Cpanel::SafeFile::safeclose( $shadow_fh, $slock );

    return [ { login => $login } ];
}

sub _userexists {
    my $user = shift;
    $user =~ s/[\+\r\n\s\t]//g;

    my $shadowPath = $Cpanel::homedir . '/etc/webdav/shadow';
    if ( !-e $shadowPath ) {

        # if the <homedir>/etc/webdav/shadow doesn't exist, then neither does the virtual user
        return;
    }

    my $shadow_fh = IO::Handle->new();
    my $status    = open( $shadow_fh, '<', $shadowPath );    # caller is responsible for locking the entire operation, so use a plain open
    if ( !$status ) {
        $logger ||= Cpanel::Logger->new();
        $logger->info("Could not open $shadowPath - $!");
        return;
    }

    my $userExists = 0;
    my $userRegex  = qr/^\Q$user\E:/;
    while ( my $userEntry = readline($shadow_fh) ) {
        if ( $userEntry =~ $userRegex ) {
            $userExists = 1;
            last;
        }
    }
    close($shadow_fh);

    return $userExists;

}

sub _deluser {
    my $login      = shift;
    my $skippasswd = int( shift || 0 );
    $login =~ s/[\+\r\n\s\t]//g;

    my @PDFS = $Cpanel::homedir . '/etc/webdav/shadow';
    if ( !$skippasswd ) {
        push @PDFS, $Cpanel::homedir . '/etc/webdav/passwd';
    }

    my $user_deleted = 0;
    my $userRegex    = qr/^\Q$login\E:/;
    foreach my $pf (@PDFS) {
        my @ET;

        my $webdav_fh = IO::Handle->new();
        my $slock     = Cpanel::SafeFile::safeopen( $webdav_fh, '+<', $pf );
        if ( !$slock ) {
            $logger ||= Cpanel::Logger->new();
            $logger->info("Could not open $pf - $!");
            next;
        }

        my $found_user;

        while ( my $userEntry = readline($webdav_fh) ) {
            next if ( $userEntry =~ m/^\s*$/ );    #remove empty lines
            if ( $userEntry =~ $userRegex ) {
                $found_user = 1;
                next;
            }
            push @ET, $userEntry;
        }
        if ( defined $found_user ) {
            seek $webdav_fh, 0, 0;
            print $webdav_fh join( '', @ET );
            truncate( $webdav_fh, tell $webdav_fh );
            $user_deleted = 1;
        }
        Cpanel::SafeFile::safeclose( $webdav_fh, $slock );
    }

    if ( !$user_deleted ) {
        $locale ||= Cpanel::Locale->get_handle();
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'Unable to delete user; user “[_1]” does not exist.', $login );
    }

    return $user_deleted;
}

sub _setupdirs {
    Cpanel::SafeDir::MK::safemkdir( $Cpanel::homedir . '/etc/webdav', '0700' );
    return;
}

sub api2_addwebdisk {
    my %OPTS = @_;

    my $user             = $OPTS{'user'};
    my $password         = $OPTS{'password'};
    my $password_hash    = $OPTS{'password_hash'};
    my $digest_auth_hash = $OPTS{'digest_auth_hash'};
    my $domain           = $OPTS{'domain'};
    my $homedir          = $OPTS{'homedir'};
    my $private          = $OPTS{'private'};
    my $perms            = $OPTS{'perms'};
    my $enabledigest =
      exists $OPTS{'digestauth'}
      ? $OPTS{'digestauth'}
      : $OPTS{'enabledigest'};
    $locale ||= Cpanel::Locale->get_handle();

    ## PASSWORD AUDIT (complete): cp's webdisk. $password is not encoded
    ##  modify=none to ensure passwords like '&a1x2)W7r3L1' work

    $user   =~ s/[\@\+\r\n\s\t]//g;
    $domain =~ s/[\@\+\r\n\s\t]//g;

    my $app = 'webdisk';

    ##
    ## Validate the inputs
    ##

    if ( !$user ) {
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext('No username provided for web disk account creation.');
        return;
    }

    my $full_username = $user . '@' . $domain;
    eval { Cpanel::Validate::VirtualUsername::validate_for_creation_or_die($full_username) };
    if ( my $exception = $@ ) {
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'The name “[_1]” is invalid: [_2]', $full_username, Cpanel::Exception::get_string($exception) );
        return;
    }

    if ( !( $password xor $password_hash ) ) {
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext('You must provide a password or a password hash to create a [asis,Web Disk] account.');
        return;
    }

    if ( !$homedir ) {
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext('No home directory provided for Web Disk account creation.');
        return;
    }

    if ( $password && !Cpanel::PasswdStrength::Check::check_password_strength( 'pw' => $password, 'app' => $app ) ) {
        my $required_strength = Cpanel::PasswdStrength::Check::get_required_strength($app);
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'Sorry, the password you selected cannot be used because it is too weak and would be too easy to guess. Please select a password with strength rating of [numf,_1] or higher.', $required_strength );
        print STDERR $Cpanel::CPERROR{$Cpanel::context};
        print $Cpanel::CPERROR{$Cpanel::context};
        return;
    }

    $perms ||= 'rw';
    if ( $perms !~ /^r[wo]$/ ) {
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext('The only legal values for [asis,perms] are [asis,“rw”] and [asis,“ro”].');
        return;
    }

    ##
    ## After input validation, but before user existence check, establish locks
    ##

    _setupdirs();

    my $passwd_file = $Cpanel::homedir . '/etc/webdav/passwd';
    my $shadow_file = $Cpanel::homedir . '/etc/webdav/shadow';

    # TODO: switch to Cpanel::Transaction::File::Raw
    _safe_create_file($passwd_file);    # make sure we have a 0600 file in place
    my $passwd_fh   = IO::Handle->new();
    my $passwd_lock = Cpanel::SafeFile::safeopen( $passwd_fh, '>>', $passwd_file );
    if ( !$passwd_lock ) {
        $logger ||= Cpanel::Logger->new();
        $logger->warn("Could not append to $passwd_file");
        return;
    }
    chmod( 0600, $passwd_file );

    # TODO: switch to Cpanel::Transaction::File::Raw
    _safe_create_file($shadow_file);    # make sure we have a 0600 file in place
    my $shadow_fh   = IO::Handle->new();
    my $shadow_lock = Cpanel::SafeFile::safeopen( $shadow_fh, '>>', $shadow_file );
    if ( !$shadow_lock ) {
        $logger ||= Cpanel::Logger->new();
        $logger->warn("Could not append to $shadow_file");
        return;
    }
    chmod( 0600, $shadow_file );

    my $release_locks = sub {
        Cpanel::SafeFile::safeclose( $passwd_fh, $passwd_lock );
        Cpanel::SafeFile::safeclose( $shadow_fh, $shadow_lock );
    };

    ##
    ## Once we have the files locked, check to make sure the user doesn't already exist.
    ## This has to be done after we have the lock to prevent a race condition.
    ##

    if ( _userexists("${user}\@${domain}") ) {
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'The user “[_1]” already exists.', "${user}\@${domain}" );
        $release_locks->();
        return;
    }

    ##
    ## And then proceed with the actual work
    ##

    $homedir = $Cpanel::homedir . '/' . $homedir;
    $homedir =~ s{//+}{/}g;
    $homedir = Cpanel::SafeDir::safedir($homedir);

    if ($private) {
        Cpanel::SafeDir::MK::safemkdir( $homedir, '0700' );
    }
    else {
        Cpanel::SafeDir::MK::safemkdir( $homedir, '0755' );
    }

    my $random = Cpanel::Rand::Get::getranddata(256);

    my $cpass;
    if ( ( $password || $password_hash ) eq '*' ) {
        $cpass = '*';
    }
    elsif ($password_hash) {
        if ( $password_hash !~ /^\$[0-9]\$/ ) {
            $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext('Unexpected data provided for password hash.');    # protect against cleartext password accidentally being provided and stored in this field
            $release_locks->();
            return;
        }
        $cpass = $password_hash;
    }
    else {
        while ( !$cpass || $cpass =~ /:/ ) {
            $cpass = Cpanel::Auth::Generate::generate_password_hash($password);
        }
    }
    my ( undef, undef, $uid, $gid, undef, undef, $gcos, $dir, $shell, undef ) = Cpanel::PwCache::getpwnam($Cpanel::user);

    # Since we define this format we can add anything we like here as long as Cpanel::HTTPDaemonApp is updated as well
    print $passwd_fh "${user}\@${domain}:x:${uid}:${gid}:${gcos}:${homedir}:${shell}:$perms\n";

    my $realm = Cpanel::Auth::Digest::Realm::get_realm();

    $digest_auth_hash = !$enabledigest ? '' : $digest_auth_hash ? $digest_auth_hash : _md5_hex("$user\@$domain:$realm:$password");
    $digest_auth_hash =~ /^[0-9a-f]*$/ or die;
    my $passwdtime = _shadow_time();
    print $shadow_fh "${user}\@${domain}:${cpass}:${passwdtime}::::::${digest_auth_hash}\n";

    # Hold both locks until we're sure everything is done.
    $release_locks->();

    return [ { user => $user, domain => $domain, login => "$user\@$domain", 'enabledigest' => $enabledigest ? 1 : 0, 'perms' => $perms } ];
}

sub api2_delwebdisk {
    my %OPTS = @_;

    my $login = $OPTS{'login'};
    $login =~ s/[\+\r\n\s\t]//g;

    my $retval = _deluser($login);

    if ( !$retval ) {

        # _deluser will set CPERROR
        return;
    }

    my ( $user, $domain ) = split( '@', $login );
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
        my $delete_ok = Cpanel::UserManager::Storage::delete_annotation( $usermanager_obj, 'webdisk' );
        if ( !$delete_ok ) {
            $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'The system failed to delete the annotation record for the [asis,Web Disk] account “[_1]”.', $login );
            return;
        }
    }

    return [ { login => $login } ];
}

sub api2_listwebdisks {

    #NOTE: No authz here because there is no point to restricting this information.

    my %OPTS = @_;
    my $regex;
    if ( $OPTS{'regex'} ) {
        eval {
            local $SIG{'__DIE__'} = sub { return };
            $regex = qr/$OPTS{'regex'}/i;
        };
        if ( !$regex ) {
            $locale ||= Cpanel::Locale->get_handle();
            $Cpanel::CPERROR{'subdomain'} = $locale->maketext('Invalid regex.');
            return;
        }
    }
    my $proxydomain = '';
    my $main_port   = '2077';
    my $ssl_port    = '2078';
    if ( Cpanel::ProxyUtils::proxied() ) {
        Cpanel::ProxyUtils::proxyaddress('webdisk');
        $proxydomain = $Cpanel::CPVAR{'new_proxy_domain'};
        $ssl_port    = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();
        $main_port   = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();
    }
    my $has_no_digest_accounts = 0;
    my %HAS_DIGEST_AUTH;
    my @RSD;

    my $home_dir = $OPTS{'home_dir'} ? $OPTS{'home_dir'} : $Cpanel::homedir;

    if ( -e "$home_dir/etc/webdav/shadow" ) {
        my $shadow_fh = IO::Handle->new();
        my $slock     = Cpanel::SafeFile::safeopen( $shadow_fh, '<', "$home_dir/etc/webdav/shadow" );
        if ( !$slock ) {
            $logger ||= Cpanel::Logger->new();
            $logger->info("Could not read from $home_dir/etc/webdav/shadow: $!");
            return;
        }
        my ( $user, $digestha1 );
        while ( my $userEntry = readline($shadow_fh) ) {
            chomp($userEntry);
            ( $user, $digestha1 ) = ( split( /:/, $userEntry ) )[ 0, 8 ];
            $HAS_DIGEST_AUTH{$user} = $digestha1 ? 1 : 0;
            if ( !$digestha1 ) { $has_no_digest_accounts = 1; }
        }
        Cpanel::SafeFile::safeclose( $shadow_fh, $slock );
    }

    if ( -e "$home_dir/etc/webdav/passwd" ) {
        my $passwd_fh = IO::Handle->new();
        my $slock     = Cpanel::SafeFile::safeopen( $passwd_fh, '<', "$home_dir/etc/webdav/passwd" );
        if ( !$slock ) {
            $logger ||= Cpanel::Logger->new();
            $logger->info("Could not read from $home_dir/etc/webdav/passwd: $!");
            return;
        }

        my $users_domain_regex = join '|', map { "\Q$_\E" } @Cpanel::DOMAINS;
        $users_domain_regex = qr/^($users_domain_regex)$/;

        while ( my $userEntry = readline($passwd_fh) ) {
            chomp $userEntry;
            my ( $login, $homedir, $perms ) = ( split( /:/, $userEntry ) )[ 0, 5, 7 ];
            if ( $regex && $login !~ $regex ) { next; }
            my $reldir = $homedir;
            $reldir =~ s/^$home_dir\/?//g;
            $perms //= 'rw';

            my ( $user, $domain ) = split( /\@/, $login );
            if ( $OPTS{'check_primary_domain'} ) {

                # don't check if domain is present in list of domains other than main
                next if $domain =~ $users_domain_regex;
            }
            else {
                # don't check if domain is NOT present in list of domains other than main
                next if $domain !~ $users_domain_regex;
            }
            $domain = $proxydomain if $proxydomain;

            # If the homedir doesn't exist, it's private.
            my $private = ( ( ( stat($homedir) )[2] // 0 ) & 0004 ) ? 0 : 1;
            push( @RSD, { login => $login, domain =>, $domain, user => $user, homedir => $homedir, reldir => $reldir, private => $private, sslport => $ssl_port, mainport => $main_port, 'hasdigest' => $HAS_DIGEST_AUTH{$login}, 'perms' => ( $perms eq 'ro' ? 'ro' : 'rw' ) } );
        }
        Cpanel::SafeFile::safeclose( $passwd_fh, $slock );

        @RSD = sort { $a->{'login'} cmp $b->{'login'} } @RSD;
    }
    $Cpanel::CPVAR{'all_accounts_havedigest'} = $has_no_digest_accounts ? 0 : 1;
    return @RSD;
}

sub api2_setstatus {
    my %OPTS = @_;

    my $login = $OPTS{'login'};
    my $on    = $OPTS{'on'} || 0;

    my @WEBDISKS = api2_listwebdisks();
    foreach my $webdisk (@WEBDISKS) {
        if ( $login && $webdisk->{'login'} eq $login ) {
            if ( $on eq '1' ) {
                chmod( 0700, $webdisk->{'homedir'} );
            }
            else {
                chmod( 0755, $webdisk->{'homedir'} );
            }
        }
    }
    return ( { 'private' => int $on } );
}

sub api2_hasdigest {

    #NOTE: No authz here because there is no point to restricting this information.

    return { 'hasdigest' => ( $Cpanel::CPVAR{'hasdigest'} = Cpanel::AdminBin::adminrun( 'security', 'HASDIGEST', 0 ) ) };
}

sub api2_set_digest_auth {
    my %OPTS = @_;

    $locale ||= Cpanel::Locale->get_handle();
    my $login    = $OPTS{'login'};
    my $password = $OPTS{'password'};
    my $enabledigest =
      exists $OPTS{'digestauth'}
      ? $OPTS{'digestauth'}
      : $OPTS{'enabledigest'};

    if ( !defined $enabledigest ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext( 'The “[_1]” parameter is required.', 'enabledigest' ) } ];
    }
    elsif ( !length $login ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext( 'The “[_1]” parameter is required.', 'login' ) } ];
    }
    elsif ( $enabledigest && !length $password ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext('No password supplied.') } ];
    }

    # TODO: switch to Cpanel::Transaction::File::Raw
    _safe_create_file( $Cpanel::homedir . '/etc/webdav/shadow' );    # make sure we have a 0600 file in place
    my $shadow_fh = IO::Handle->new();
    my $slock     = Cpanel::SafeFile::safeopen( $shadow_fh, '+<', $Cpanel::homedir . '/etc/webdav/shadow' );
    if ( !$slock ) {
        $logger ||= Cpanel::Logger->new();
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'Could not append to “[_1]”.', "$Cpanel::homedir/etc/webdav/shadow" );
        $logger->warn("Could not append to $Cpanel::homedir/etc/webdav/shadow");
        return;
    }
    chmod( 0600, $Cpanel::homedir . '/etc/webdav/shadow' );
    my $login_regex = qr/^\Q$login\E:/;

    my ( $founduser, $modified, @file );
    while ( my $line = readline($shadow_fh) ) {
        next if ( $line =~ m/^\s*$/ );    #remove empty lines
        if ( $line =~ $login_regex ) {
            my ( $user, $cpass, $timestamp, @additional ) = split( m/:/, $line );
            chomp( $additional[-1] );
            if ( !length $cpass ) {
                Cpanel::SafeFile::safeclose( $shadow_fh, $slock );
                return [ { 'result' => 0, 'reason' => $locale->maketext('Digest Authentication could not be enabled because we could not fetch the current crypted password.') } ];
            }
            elsif ( $cpass =~ m/(?:\*LOCKED\*|^\!\!)/ ) {
                Cpanel::SafeFile::safeclose( $shadow_fh, $slock );
                return [ { 'result' => 0, 'reason' => $locale->maketext('Digest Authentication could not be enabled because the account is suspended.') } ];
            }
            elsif ($enabledigest) {
                Cpanel::LoadModule::load_perl_module('Cpanel::CheckPass::UNIX');
                if ( Cpanel::CheckPass::UNIX::checkpassword( $password, $cpass ) ) {
                    $modified = 1;
                    my $realm = Cpanel::Auth::Digest::Realm::get_realm();
                    $timestamp = _shadow_time();
                    $additional[5] = _md5_hex("$login:$realm:$password");
                }
                else {
                    Cpanel::SafeFile::safeclose( $shadow_fh, $slock );
                    return [ { 'result' => 0, 'reason' => $locale->maketext('Digest Authentication could not be enabled because the supplied password does not match the password previously provided.') } ];
                }
            }
            else {
                $modified = 1;
                $additional[5] = '';
            }
            $founduser = 1;
            push @file, join( ':', $user, $cpass, $timestamp, @additional ) . "\n";
        }
        else {
            push @file, $line;
        }
    }
    if ($modified) {
        seek( $shadow_fh, 0, 0 );
        print {$shadow_fh} join( "\n", map { s/\n//gr } @file ) . "\n";
        truncate( $shadow_fh, tell($shadow_fh) );
    }
    Cpanel::SafeFile::safeclose( $shadow_fh, $slock );

    if ( !$founduser ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext('The specified user does not exist.') } ];
    }
    elsif ($modified) {
        return [ { 'result' => 1, 'reason' => ( $enabledigest ? $locale->maketext('Digest Authentication enabled.') : $locale->maketext('Digest Authentication disabled.') ) } ];
    }
    else {
        return [ { 'result' => 0, 'reason' => $locale->maketext('Unknown error.') } ];
    }

}

sub api2_set_perms {
    my %OPTS = @_;

    $locale ||= Cpanel::Locale->get_handle();
    my $login = $OPTS{'login'};
    my $perms = $OPTS{'perms'};

    if ( !defined $perms ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext( 'The “[_1]” parameter is required.', 'perms' ) } ];
    }
    elsif ( !length $login ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext( 'The “[_1]” parameter is required.', 'login' ) } ];
    }

    # Validate the perms parameter values
    my $perms_valid = 0;
    for my $valid (qw(ro rw)) {
        $perms_valid = 1 if $valid eq $perms;
    }
    if ( !$perms_valid ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext( 'The “[_1]” parameter must have a value of either “[asis,ro]” or “[asis,rw]”.', 'perms' ) } ];
    }

    # TODO: switch to Cpanel::Transaction::File::Raw
    _safe_create_file( $Cpanel::homedir . '/etc/webdav/passwd' );    # make sure we have a 0600 file in place
    my $passwd_fh = IO::Handle->new();
    my $slock     = Cpanel::SafeFile::safeopen( $passwd_fh, '+<', $Cpanel::homedir . '/etc/webdav/passwd' );
    if ( !$slock ) {
        $logger ||= Cpanel::Logger->new();
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'Could not write to “[_1]”.', "$Cpanel::homedir/etc/webdav/passwd" );
        $logger->warn("Could not write to $Cpanel::homedir/etc/webdav/passwd");
        return;
    }
    chmod( 0600, $Cpanel::homedir . '/etc/webdav/passwd' );
    my $login_regex = qr/^\Q$login\E:/;

    my ( $founduser, $modified, $no_change, @file );
    while ( my $line = readline($passwd_fh) ) {
        next if ( $line =~ m/^\s*$/ );    #remove empty lines
        if ( $line =~ $login_regex ) {
            my (@entry) = split( m/:/, $line );
            chomp( $entry[-1] );
            my $new_entry = $perms eq 'ro' ? 'ro' : 'rw';
            if ( !$entry[7] || $entry[7] ne $new_entry ) {
                $modified = 1;
                $entry[7] = $new_entry;
            }
            else {
                $no_change = 1;
            }
            $founduser = 1;
            push @file, join( ':', @entry ) . "\n";
        }
        else {
            push @file, $line;
        }
    }
    if ($modified) {
        seek( $passwd_fh, 0, 0 );
        print {$passwd_fh} join( "\n", map { s/\n//gr } @file ) . "\n";
        truncate( $passwd_fh, tell($passwd_fh) );
    }
    Cpanel::SafeFile::safeclose( $passwd_fh, $slock );

    if ( !$founduser ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext('The specified user does not exist.') } ];
    }
    elsif ( $founduser and ( $modified || $no_change ) ) {
        return [ { 'result' => 1, 'reason' => $locale->maketext( 'Permissions set to: [_1]', ( $perms eq 'ro' ? $locale->maketext('read-only') : $locale->maketext('read-write') ) ) } ];
    }
    else {
        return [ { 'result' => 0, 'reason' => $locale->maketext('Unknown error.') } ];
    }
}

sub api2_set_homedir {
    my %OPTS = @_;

    $locale ||= Cpanel::Locale->get_handle();
    my $login   = $OPTS{'login'};
    my $homedir = $OPTS{'homedir'};
    my $private = $OPTS{'private'};

    if ( !defined $homedir ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext( 'The “[_1]” parameter is required.', 'homedir' ) } ];
    }
    elsif ( !length $login ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext( 'The “[_1]” parameter is required.', 'login' ) } ];
    }

    # TODO: switch to Cpanel::Transaction::File::Raw
    _safe_create_file( $Cpanel::homedir . '/etc/webdav/passwd' );    # make sure we have a 0600 file in place
    my $passwd_fh = IO::Handle->new();
    my $slock     = Cpanel::SafeFile::safeopen( $passwd_fh, '+<', $Cpanel::homedir . '/etc/webdav/passwd' );
    if ( !$slock ) {
        $logger ||= Cpanel::Logger->new();
        $Cpanel::CPERROR{$Cpanel::context} = $locale->maketext( 'Could not write to “[_1]”.', "$Cpanel::homedir/etc/webdav/passwd" );
        $logger->warn("Could not write to $Cpanel::homedir/etc/webdav/passwd");
        return;
    }
    chmod( 0600, $Cpanel::homedir . '/etc/webdav/passwd' );
    my $login_regex = qr/^\Q$login\E:/;

    $homedir = $Cpanel::homedir . '/' . $homedir;
    $homedir =~ s{//+}{/}g;
    $homedir = Cpanel::SafeDir::safedir($homedir);

    if ($private) {
        Cpanel::SafeDir::MK::safemkdir( $homedir, '0700' );
    }
    else {
        Cpanel::SafeDir::MK::safemkdir( $homedir, '0755' );
    }

    my $relhomedir = $homedir;
    $relhomedir =~ s/^\Q$Cpanel::homedir\E//g;

    my ( $founduser, $modified, @file, $seen );
    while ( my $line = readline($passwd_fh) ) {
        next if ( $line =~ m/^\s*$/ );    #remove empty lines
        if ( $line =~ $login_regex ) {
            my (@entry) = split( m/:/, $line );
            chomp( $entry[-1] );
            my $new_entry = $homedir;
            if ( !$entry[5] || $entry[5] ne $new_entry ) {
                $modified = 1;
                $entry[5] = $new_entry;
            }
            else {
                $seen = 1;
            }
            $founduser = 1;
            push @file, join( ':', @entry ) . "\n";
        }
        else {
            push @file, $line;
        }
    }
    if ($modified) {
        seek( $passwd_fh, 0, 0 );
        print {$passwd_fh} join( "\n", map { s/\n//gr } @file ) . "\n";
        truncate( $passwd_fh, tell($passwd_fh) );
    }
    Cpanel::SafeFile::safeclose( $passwd_fh, $slock );

    if ( !$founduser ) {
        return [ { 'result' => 0, 'reason' => $locale->maketext('The specified user does not exist.') } ];
    }
    elsif ($modified) {
        return [ { 'result' => 1, 'reason' => $locale->maketext( 'Home Directory set to: [_1]', $relhomedir ), 'reldir' => $relhomedir } ];
    }
    elsif ($seen) {
        return [ { 'result' => 1, 'reason' => $locale->maketext( 'Home Directory was already set to “[_1]”.', $relhomedir ), 'reldir' => $relhomedir } ];
    }
    else {
        return [ { 'result' => 0, 'reason' => $locale->maketext('Unknown error.') } ];
    }
}

my $webdisk_feature_xss_checked_modify_none = {
    needs_role    => 'WebDisk',
    needs_feature => 'webdisk',
    modify        => 'none',
    xss_checked   => 1,
};

my $webdisk_feature = {
    needs_role    => 'WebDisk',
    needs_feature => 'webdisk',
};

my $allow_demo = {
    needs_role => 'WebDisk',
    allow_demo => 1,
};

our %API = (
    setstatus       => $webdisk_feature,
    hasdigest       => $allow_demo,
    addwebdisk      => $webdisk_feature_xss_checked_modify_none,
    set_digest_auth => $webdisk_feature_xss_checked_modify_none,
    set_homedir     => $webdisk_feature_xss_checked_modify_none,
    set_perms       => $webdisk_feature_xss_checked_modify_none,
    passwdwebdisk   => $webdisk_feature_xss_checked_modify_none,
    delwebdisk      => $webdisk_feature,
    listwebdisks    => $allow_demo,
);

$_->{'needs_role'} = 'WebDisk' for values %API;

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub _safe_create_file {
    my $file = shift;

    my $original_umask = umask();

    my $_fh;
    if ( sysopen( $_fh, $file, $Cpanel::Fcntl::Constants::O_EXCL | $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_TRUNC | $Cpanel::Fcntl::Constants::O_CREAT, 0600 ) ) {
        close($_fh);
    }

    return;
}

1;
