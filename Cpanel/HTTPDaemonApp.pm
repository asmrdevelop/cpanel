package Cpanel::HTTPDaemonApp;

# cpanel - Cpanel/HTTPDaemonApp.pm                 Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::PwCache::PwFile              ();
use Cpanel::PwCache::Build               ();
use Cpanel::PwCache                      ();
use Cpanel::AccessIds::SetUids           ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::CheckPass::UNIX              ();
use Cpanel::Config::Hulk                 ();
use Cpanel::Config::LoadCpUserFile       ();
use Cpanel::Hulk                         ();
use Cpanel::Hulk::Key                    ();
use Cpanel::PwCache                      ();
use Cpanel::PwCache::Helpers             ();
use Cpanel::Rand                         ();
use Cpanel::PwDiskCache                  ();    # used for tie
use Cpanel::SV                           ();

my $cphulk = Cpanel::Hulk->new;
my %SECURE_PWCACHE;

our $PWENT_USER              = 0;
our $PWENT_ENCRYPTED_PASS    = 1;
our $PWENT_UID               = 2;
our $PWENT_GID               = 3;
our $PWENT_ROOTDIR           = 4;
our $PWENT_MTIME             = 5;
our $PWENT_PASSWD_CACHE_DIR  = 6;
our $PWENT_LAST_CHANGED_TIME = 7;
our $PWENT_DIGEST_HA1        = 8;
our $PWENT_SYSUSERHOME       = 9;
our $PWENT_PERMS             = 10;

sub setup_getpwnam {
    my ( $conf, $auth_user, $authtype ) = @_;

    my $system_user;

    return [] if !$auth_user;

    if ( !$conf->{'cache'}{$auth_user}{'getpwnam'} ) {
        my ( $authmtime, $passwd_cache_dir );
        if ( !$conf->{'_system_users_only'} && $auth_user =~ m{(.*)\@(.*)} ) {
            my ( $localpart, $domain ) = ( $1, $2 );

            #
            # 1. If the caller requests that we authenticate based on this cPanel account's known
            # webmail users, then we want to look up from here:
            #
            #     /home/<thisuser>/etc/<thisdomain>/shadow
            #
            # And, given a webmail user jane@example.com, we want to look up a passwd file row with
            # a username field containing only
            #
            #     jane
            #
            # 2. On the other hand, for WebDAV requests, which have their own separate list of
            # accounts, we want this file:
            #
            #     /home/<thisuser>/etc/webdav/shadow
            #
            # And given a cPanel Web Disk user jane@example.com, we want to look up a passwd file
            # row with a username containing
            #
            #     jane@example.com
            #

            my ( $directory, $passwd_lookup_username ) =
              $conf->{'_mail_users'}
              ? ( $domain, $localpart )
              : ( 'webdav', $auth_user );

            if ( $system_user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'default' => '', 'skiptruelookup' => 1 } ) ) {

                # this is the same logic used in Cpanel::MailAuth
                # only if the domain of the virtual user is valid
                # should we even look for the virtual user on the system
                my ( $uid, $gid, $mainroot ) = ( Cpanel::PwCache::getpwnam($system_user) )[ 2, 3, 7 ];
                if ($mainroot) {
                    $passwd_cache_dir = "$mainroot/etc/$directory/\@pwcache";
                    my $shadow_mtime = ( stat("$mainroot/etc/$directory/shadow") )[9];
                    my $passwd_mtime = ( stat("$mainroot/etc/$directory/passwd") )[9];
                    $authmtime = ( $passwd_mtime > $shadow_mtime ? $passwd_mtime : $shadow_mtime );
                    require Cpanel::PwFileCache;
                    my $pwcache_ref = Cpanel::PwFileCache::load_pw_cache(
                        {
                            'passwd_cache_dir'  => $passwd_cache_dir,
                            'passwd_cache_file' => $auth_user,
                            'quota_file_mtime'  => 0,
                            'passwd_file_mtime' => $authmtime,
                        }
                    );

                    if ( ( $authtype =~ /digest/i ? defined $pwcache_ref->{'digest-ha1'} : defined $pwcache_ref->{'passwd'} ) && defined $pwcache_ref->{'homedir'} && $pwcache_ref->{'perms'} ) {
                        @{ $conf->{'cache'}{$auth_user}{'getpwnam'} } = ( $auth_user, $pwcache_ref->{'passwd'}, $uid, $gid, $pwcache_ref->{'homedir'}, $pwcache_ref->{'mtime'}, $passwd_cache_dir, 0, $pwcache_ref->{'digest-ha1'}, $mainroot, $pwcache_ref->{'perms'} );
                    }
                    else {
                        my ( $shadow_entry_line, $passwd_entry_line );
                        my $read_shadow_file = sub { $shadow_entry_line = Cpanel::PwCache::PwFile::get_line_from_pwfile( "$mainroot/etc/$directory/shadow", $passwd_lookup_username ) };
                        my $read_passwd_file = sub { $passwd_entry_line = Cpanel::PwCache::PwFile::get_line_from_pwfile( "$mainroot/etc/$directory/passwd", $passwd_lookup_username ) };

                        Cpanel::AccessIds::ReducedPrivileges::call_as_user( $read_shadow_file, $system_user );
                        Cpanel::AccessIds::ReducedPrivileges::call_as_user( $read_passwd_file, $system_user );

                        if ($shadow_entry_line) {
                            my ( $u, $ep, $digest_ha1 ) = @{$shadow_entry_line}[ 0, 1, 8 ];
                            $digest_ha1 =~ s/[\r\n]//g;
                            if ($passwd_entry_line) {
                                my $docroot = $passwd_entry_line->[5];
                                my $perms   = $passwd_entry_line->[7] || 'rw';    #default to readwrite for 11.32 compat
                                $conf->{'cache'}{$auth_user}{'getpwnam'} = [ $u, $ep, $uid, $gid, $docroot, $authmtime, $passwd_cache_dir, 0, $digest_ha1, $mainroot, $perms ];
                            }
                            else {
                                $conf->{'cache'}{$auth_user}{'getpwnam'} = [];
                            }
                        }
                    }
                }
            }
        }
        else {
            @{ $conf->{'cache'}{$auth_user}{'getpwnam'} } = ( Cpanel::PwCache::getpwnam($auth_user) )[ 0, 1, 2, 3, 7, 12, 0, 10 ];
            if ( $conf->{'cache'}{$auth_user}{'getpwnam'}->[$PWENT_USER] ) {
                $system_user      = $auth_user;
                $authmtime        = $conf->{'cache'}{$auth_user}{'getpwnam'}->[$PWENT_MTIME];
                $passwd_cache_dir = "/var/cpanel/\@pwcache";
                require Cpanel::PwFileCache;
                my $pwcache_ref = Cpanel::PwFileCache::load_pw_cache(
                    {
                        'passwd_cache_dir'  => $passwd_cache_dir,
                        'passwd_cache_file' => $auth_user,
                        'quota_file_mtime'  => 0,
                        'passwd_file_mtime' => $authmtime,
                    }
                );

                if ( ( $authtype =~ /digest/i ? defined $pwcache_ref->{'digest-ha1'} : defined $pwcache_ref->{'passwd'} ) && defined $pwcache_ref->{'homedir'} ) {
                    $conf->{'cache'}{$auth_user}{'getpwnam'}->[$PWENT_DIGEST_HA1] = $pwcache_ref->{'digest-ha1'};
                }
                else {
                    require Cpanel::Auth::Digest::DB;
                    $conf->{'cache'}{$auth_user}{'getpwnam'}->[$PWENT_DIGEST_HA1] = Cpanel::PwCache::PwFile::get_keyvalue_from_pwfile( $Cpanel::Auth::Digest::DB::file, 1, $auth_user );
                }
                $conf->{'cache'}{$auth_user}{'getpwnam'}->[$PWENT_PASSWD_CACHE_DIR] = "/var/cpanel/\@pwcache";
                $conf->{'cache'}{$auth_user}{'getpwnam'}->[$PWENT_SYSUSERHOME]      = $conf->{'cache'}{$auth_user}{'getpwnam'}->[$PWENT_ROOTDIR];
                $conf->{'cache'}{$auth_user}{'getpwnam'}->[$PWENT_PERMS]            = 'rw';                                                         #system user always rw as they own their account and there is no reason to restrict them
            }
        }
    }

    if ( !defined $conf->{'cache'}{$auth_user}{'cpuserfile'} ) {
        $conf->{'cache'}{$auth_user}{'cpuserfile'} = $system_user ? _load_subset_of_cpuserfile( $system_user, $auth_user eq $system_user ) : {};
    }

    Cpanel::SV::untaint( $conf->{'cache'}{$auth_user}{'getpwnam'}->[$PWENT_ROOTDIR] );

    return $conf->{'cache'}{$auth_user}{'getpwnam'};
}

sub _load_subset_of_cpuserfile {
    my $user           = shift;
    my $is_system_user = shift;
    $user =~ s/\///g;

    my %cpuser_info = ( 'WEBDAV' => 1, 'DEMO' => 0 );
    my $cpuser_ref  = Cpanel::Config::LoadCpUserFile::loadcpuserfile($user);
    $cpuser_info{'WEBDAV'} = $cpuser_ref->{WEBDAV} if exists $cpuser_ref->{WEBDAV};
    $cpuser_info{'DEMO'}   = $cpuser_ref->{DEMO}   if exists $cpuser_ref->{DEMO};

    # When z-push is executed via cpdavd, it needs to know the domains related to a system user.
    if ($is_system_user) {
        my @md = $cpuser_ref->{DOMAIN};
        push @md, grep { not /\*/ } @{ $cpuser_ref->{DOMAINS} };
        $ENV{MAIL_DOMAINS} = join "|", @md;
    }
    return \%cpuser_info;
}

sub login_init {    ## no critic qw(ProhibitManyArgs)
    my ( $conf, $user, $uid, $gid, $current_uid, $userhomedir, $skip_inc_wipe ) = @_;
    $conf->{'badlogins'}{$user} = 0;
    $conf->{'cache'}{$user}{'lastlogin'} = time;

    $current_uid = $> if !defined $current_uid;

    $userhomedir ||= Cpanel::PwCache::gethomedir($uid);

    if ( $uid != $current_uid || 0 == $current_uid ) {
        $ENV{'REMOTE_USER'} = $user;

        untie %SECURE_PWCACHE;
        Cpanel::PwCache::Helpers::deinit();

        # See case SEC-333.
        # It does not make sense to localize INC, since we want this change to affect the entire process.

        # cpdavd w/ caldav support needs @INC to load several modules at runtime (mostly DateTime sub modules)
        # There is also no vector we can determine for a user to call into this code from the daemon, and it drops
        # privs to the user for processing all requests
        if ( !$skip_inc_wipe ) {
            @INC = ();    ## no critic qw(RequireLocalizedPunctuationVars)
        }

        if ( !chroot($userhomedir) ) {
            die "Failed to chroot to directory '$userhomedir': $!";
        }
        chdir("/");
        Cpanel::AccessIds::SetUids::setuids( $uid, $gid );
    }

    return;
}

sub pre_auth_request {
    my ( $conf, $user, $auth_user ) = @_;
    $conf->{'badlogins'}{$auth_user}++;
    $conf->{'cache'}{$user}{'lastlogin'} = 0;
    return;
}

sub authenticate {    ## no critic qw(ProhibitManyArgs)
    my ( $auth_user, $auth_request, $peerhost, $authtype, $pwnam, $now, $current_uid, $sockhost ) = @_;

    my $results = { reason => '' };    # reason detail will be added if digest auth is used

    if ( $auth_user eq '' ) { return ( 0, $results ); }

    my $authok    = 0;
    my $suspended = 0;

    my $system_user = ( Cpanel::PwCache::getpwuid( $pwnam->[$PWENT_UID] ) )[0];
    my $cpuser_ref  = Cpanel::Config::LoadCpUserFile::loadcpuserfile($system_user);

    if ( $cpuser_ref->{'SUSPENDED'} ) {
        $suspended = 1;
    }

    if ( !$suspended ) {
        if ( $authtype =~ /digest/i ) {
            require Cpanel::Auth::Digest;
            ( $authok, $results ) = Cpanel::Auth::Digest::do_digest_auth(
                'digest_ha1'   => $pwnam->[$PWENT_DIGEST_HA1],
                'auth_request' => $auth_request,
                'user'         => $auth_user,
                'current_uid'  => $current_uid,
            );
        }
        else {
            my $auth_pass = $auth_request->{'password'};
            my $encpass   = $pwnam->[$PWENT_ENCRYPTED_PASS];
            if ( $auth_user && Cpanel::CheckPass::UNIX::checkpassword( $auth_pass, $encpass ) ) {
                $authok = 1;
            }
            else {
                my @caller = caller();
                if ( $caller[0] eq 'libexec::cpdavd' ) {    # This is already only called from cpdavd, but this check will help limit it in the future a bit
                                                            # See if this is a cpses user from webmail connecting to cpdavd for calendar/contacts
                    require Cpanel::Session::Constants;
                    require Cpanel::Session::Temp::Check;
                    my $session_prefix = $Cpanel::Session::Constants::TEMP_USER_PREFIX;
                    my $session_sep    = $Cpanel::Session::Constants::TEMP_SEPARATOR;
                    if ( $auth_request->{'password'} =~ m/^(\Q$session_prefix\E.{2}[a-z0-9]+)\Q$session_sep\E([a-zA-Z0-9\_]+)/ ) {
                        my $session_user     = $1;
                        my $session_password = $2;
                        if ( Cpanel::Session::Temp::Check::check_temp_session_password( $auth_request->{'username'}, $session_user, $session_password ) ) {
                            $authok = 1;
                        }
                    }
                }
            }
        }
    }

    if ($authok) {
        my $passwd_cache_dir        = $pwnam->[$PWENT_PASSWD_CACHE_DIR];
        my $passwd_cache_file_mtime = ( stat( $passwd_cache_dir . '/' . $auth_user ) )[9] || 0;
        if ( $passwd_cache_file_mtime <= $pwnam->[$PWENT_MTIME] || $passwd_cache_file_mtime > $now ) {
            require Cpanel::Auth::Digest::Realm;
            require Cpanel::PwFileCache;
            Cpanel::PwFileCache::save_pw_cache(
                {
                    'passwd_cache_file' => $auth_user,
                    'passwd_cache_dir'  => $passwd_cache_dir,
                    'uid'               => $auth_user =~ m/\@/ ? $pwnam->[$PWENT_UID] : 0,
                    'gid'               => $auth_user =~ m/\@/ ? $pwnam->[$PWENT_GID] : 0,
                    'keys'              => {
                        'encrypted_pass' => ( $pwnam->[$PWENT_ENCRYPTED_PASS] || '' ),
                        'quota'          => 0,
                        'realm'          => Cpanel::Auth::Digest::Realm::get_realm(),
                        'digest-ha1'     => ( $pwnam->[$PWENT_DIGEST_HA1]        || '' ),
                        'pass'           => ( $auth_request->{'password'}        || '' ),
                        'homedir'        => ( $pwnam->[$PWENT_ROOTDIR]           || '' ),
                        'lastchanged'    => ( $pwnam->[$PWENT_LAST_CHANGED_TIME] || -1 ),
                        'perms'          => ( $pwnam->[$PWENT_PERMS]             || '' ),    # '' is currently defaulting to rw when read back in for compat with 11.32 and below
                    }
                }
            );
        }
    }

    if ( Cpanel::Config::Hulk::is_enabled() && $cphulk->connect() && $cphulk->register( 'cpdavd', Cpanel::Hulk::Key::cached_fetch_key('cpdavd') ) ) {
        my $service = 'system';
        if ( $auth_user =~ /[\+\%\@]/ ) { $service = 'dav'; }

        my $ok_to_login = $cphulk->can_login(
            'user'         => $auth_user,
            'remote_ip'    => $peerhost,
            'local_ip'     => $sockhost,
            'remote_port'  => $ENV{'REMOTE_PORT'} || '',
            'local_port'   => $ENV{'SERVER_PORT'} || '',
            'status'       => $authok,
            'service'      => $service,
            'auth_service' => 'dav',
            'authtoken'    => $auth_request->{'password'},
            'deregister'   => 1,                             #disconnect
        );

        if ( $ok_to_login == &Cpanel::Hulk::HULK_ERROR || $ok_to_login == &Cpanel::Hulk::HULK_FAILED ) {
            syswrite( STDERR, "Brute force checking was skipped because cphulkd failed to process “$auth_user” from “$peerhost” for the “$service” service.\n" );
        }
        elsif ( $ok_to_login == &Cpanel::Hulk::HULK_HIT ) {
            syswrite( STDERR, "cphulkd incremented the failure count for “$auth_user” from “$peerhost” for the “$service” service.\n" );
            $authok = 0;
        }
        elsif ( $ok_to_login != &Cpanel::Hulk::HULK_OK ) {
            $authok = 0;
        }
    }

    return ( $authok, $results );
}

#
# Issue an 500 error and kills the connection.
#
# Arguments:
#   cphttpd - Cpanel::HTTPDaemonApp
#   socket  - IO::Socket::*
#   conf    - Hash with configuration options and cached data.
#   msg     - String - Message to send in the header
#   content - String - Document to send with the response.
#
sub internal_server_error {
    my ( $cphttpd, $socket, $conf, $msg, $content ) = @_;
    $msg ||= 'Internal Server Error';    # NOTE: Do not localize.
    $cphttpd->send_error( 500, $msg, $content );
    kill_connection( $cphttpd, $socket, undef, $conf );
}

#
# Issue an 403 forbidden error.
#
# Arguments:
#   cphttpd - Cpanel::HTTPDaemonApp
#   conf    - Hash with configuration options and cached data.
#   user    - User name making the request.
#
sub forbidden {
    my ( $cphttpd, $conf, $user ) = @_;
    $conf->{'cache'}{$user}{'lastlogin'} = 0;
    $cphttpd->send_error( 403, "Forbidden" );
}

#
# Issue an 503 service unavailable.
#
# Arguments:
#   cphttpd - Cpanel::HTTPDaemonApp
#   conf    - Hash with configuration options and cached data.
#   user    - User name making the request.
#   content - Optional content to send with the response
#
sub unavailable {
    my ( $cphttpd, $conf, $user, $content ) = @_;
    $conf->{'cache'}{$user}{'lastlogin'} = 0;
    $cphttpd->send_error( 503, "Service Unavailable", $content );
}

sub childhandler {
    my ( $handler, $d, $name, $pidfile, $conf ) = @_;

    $SIG{'CHLD'} = sub { $conf->{'_got_sig_chld'} = 1; };

    if ( $conf->{'_got_sig_chld'} ) {
        $conf->{'_got_sig_chld'} = 0;
        while ( ( my $thedead = waitpid( -1, 1 ) ) > 0 ) { }
    }
}

sub handle_serviceauth_request {
    my ( $cphttpd, $socket, $r, $conf, $srv_obj, $uri ) = @_;

    # $uri is untainted $r->uri
    # $r->uri() is a bit of a misnomer, it [is/can be] actually the entire URL, from protocol to GET query_string if any...
    # or more accurately, whatever is passed to HTTP::Request->new([GET|POST|ETC] => $uri);

    # http:..../serviceauth POST, http://...serviceauth? GET, http://...servcieauth/ POST, http://...serviceauth/? GET
    # but not http://serviceauth.fiddle.com, foo.serviceauth.com, howdy.com/serviceauth/mystuff
    if ( $uri =~ m/^\/?\.__cpanel__service__check__\.\/serviceauth/ ) {
        $0 = 'cpdavd - processing service auth';
        kill_connection( $cphttpd, $socket, $r, $conf ) if $< != 0;

        my $got_send_key = $r->content();

        # We need to support GET as well as POST here
        if ( !$got_send_key || ref $got_send_key ) {
            ($got_send_key) = $ENV{'QUERY_STRING'} =~ /sendkey=([^&\s]+)/;
        }
        $got_send_key =~ s/^sendkey=//g;
        my $keyok = $got_send_key eq $srv_obj->fetch_sendkey() ? 1 : 0;

        print {$socket} ( $keyok ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 401 Key Failed\r\n" ) . "Connection: close\r\n" . "Server: cpaneld\r\n" . "Content-type: text/plain\r\n\r\n" . ( $keyok ? $srv_obj->fetch_recvkey() : "key not accepted\n" );

        kill_connection( $cphttpd, $socket, $r, $conf, 141 );
    }
}

sub kill_connection {
    my ( $cphttpd, $socket, $r, $conf, $exit_code ) = @_;
    if ( ref $conf && $conf->{'debug'} ) {
        print STDERR "Closing Connection via kill_connection\n";
    }
    if ($socket) {
        $socket->flush();
        $socket->close();
    }
    exit( $exit_code ? $exit_code : 0 );
}

sub get_tmpfile {
    my ($conf) = @_;
    return Cpanel::Rand::get_tmp_file_by_name( '/tmp', $conf->{'_gettmpfilename_ext'} || '.req', );    # audit case 46806 ok
}

sub enable_pwcache {
    tie %SECURE_PWCACHE, 'Cpanel::PwDiskCache' or die "Could not init password cache";
    Cpanel::PwCache::Build::pwclearcache();                                                            # Clear cache created during load of modules, don't want the forked processes to have a static cache
    Cpanel::PwCache::Helpers::init( \%SECURE_PWCACHE, 1 );                                             #do not cache uids

}

1;
