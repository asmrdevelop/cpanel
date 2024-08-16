package Cpanel::AcctUtils::Lookup::MailUser;

# cpanel - Cpanel/AcctUtils/Lookup/MailUser.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception                       ();
use Cpanel::AccessIds::ReducedPrivileges    ();
use Cpanel::AccountProxy::Storage           ();
use Cpanel::Config::LoadCpUserFile          ();
use Cpanel::Email::DisableMailboxAutocreate ();
use Cpanel::LinkedNode::Worker::GetAll      ();
use Cpanel::PwCache::PwFile                 ();
use Cpanel::AcctUtils::DomainOwner::Tiny    ();
use Cpanel::AcctUtils::Lookup::Webmail      ();
use Cpanel::Auth::Digest::Realm             ();
use Cpanel::Hostname                        ();
use Cpanel::PwCache                         ();
use Cpanel::PwFileCache                     ();
use Cpanel::Validate::FilesystemNodeName    ();
use Cpanel::Validate::Username::Core        ();

my $user_domain_cache_mtime = 0;

sub get_username_and_mailbox_path_addition_or_die {
    my ($original_user) = @_;
    if ( index( $original_user, '_' ) == 0 && $original_user =~ m/^(_archive|_mainaccount)[+%:@]/ ) {
        my $pseudouser = $1;
        my $domain     = ( split( m{[+%:@]}, $original_user, 2 ) )[1];

        if ( !$domain ) {
            die("Failed to extract a domain from user: $original_user");
        }

        if ( my $possible_user = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'skiptruelookup' => 1, 'default' => '' } ) ) {
            if ( $pseudouser eq '_archive' ) {
                return ( $possible_user, '/archive/' . $domain );
            }
            return ( $possible_user, '' );
        }
        else {
            die("Failed to lookup domain owner of $domain");
        }
    }
    return ( $original_user, '' );
}

sub lookup_mail_user {
    my ( $user, $maibox_path_addition ) = @_;

    local $@;
    my $response = eval { lookup_mail_user_or_die( $user, $maibox_path_addition ); };

    if ( my $err = $@ ) {
        return {
            'status'    => 0,
            'statusmsg' => Cpanel::Exception::get_string_no_id($err),
        };
    }
    return $response;
}

sub lookup_mail_user_or_die {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $user, $maibox_path_addition ) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);

    $maibox_path_addition //= '';

    my $accttype = Cpanel::AcctUtils::Lookup::Webmail::is_webmail_user($user) ? 'mail' : 'system';

    # Strip primary hostname for dovecot compat
    my $hostname = Cpanel::Hostname::gethostname();
    $accttype = 'system' if ( $accttype eq 'mail' && $user =~ s{\@\Q$hostname\E$}{}i );

    my $response = {
        'status'    => 0,
        'statusmsg' => 'Unknown error while looking up user: ' . $user,
    };

    ## shadow
    my ( $encrypted_pass, $domainowner_encrypted_pass );
    ## cache
    my ( $cache_uid, $cache_gid, $passwd_cache_file, $passwd_cache_dir, $passwd_cache_file_mtime, $pass_strength );
    ## passwd
    my ( $passwd_file, $passwd_file_key, $passwd_file_mtime, $username, $uid, $gid, $homedir, $maildir, $address, $pass_change_time, $mail_base_dir, $utf8mailbox );
    ## quota
    my ( $quota_file, $quota, $quota_file_mtime );

    my $now = time();
    my $cpuser_ref;
    my $mailbox_autocreate;

    if ( $accttype eq 'mail' ) {
        my ( $subuser, $domain ) = Cpanel::AcctUtils::Lookup::Webmail::normalize_webmail_user($user);
        $response->{'normalized_user'} = $user = $address = "$subuser\@$domain";

        my $domainowner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'skiptruelookup' => 1, 'default' => '' } );

        if ( !$domainowner ) {
            die Cpanel::Exception::create( 'DomainDoesNotExist', [ name => $domain ] );
        }

        $username = $domainowner;

        my $ownerhomedir;
        ( $domainowner_encrypted_pass, $uid, $gid, $ownerhomedir ) = ( Cpanel::PwCache::getpwnam($domainowner) )[ 1, 2, 3, 7 ];

        if ( !$uid || !$gid || !$ownerhomedir || !-d $ownerhomedir ) {
            die Cpanel::Exception::create( 'UserNotFound', [ name => $domainowner ] );
        }

        $passwd_cache_file = $subuser;
        $passwd_cache_dir  = "$ownerhomedir/etc/$domain/\@pwcache";
        $passwd_file       = "$ownerhomedir/etc/$domain/shadow";
        $quota_file        = "$ownerhomedir/etc/$domain/quota";
        $maildir           = "$ownerhomedir/mail/$domain/$subuser" . $maibox_path_addition;
        $mail_base_dir     = "$ownerhomedir/mail/$domain/$subuser";
        $homedir           = "$ownerhomedir/mail/$domain/$subuser" . $maibox_path_addition;
        $passwd_file_key   = $subuser;
        $cpuser_ref        = Cpanel::Config::LoadCpUserFile::load($domainowner);
        $utf8mailbox       = $cpuser_ref->{'UTF8MAILBOX'} ? 1 : 0;

        $mailbox_autocreate = Cpanel::Email::DisableMailboxAutocreate->is_on( $ownerhomedir, $user ) ? 0 : 1;
    }
    else {
        $response->{'normalized_user'} = $user;

        $passwd_file = '/etc/shadow';
        ( $encrypted_pass, $uid, $gid, $homedir, $pass_change_time ) = ( Cpanel::PwCache::getpwnam($user) )[ 1, 2, 3, 7, 10 ];

        if ( !$uid ) {
            die Cpanel::Exception::create( 'UserNotFound', [ name => $user ] );
        }

        $username          = $user;
        $passwd_cache_file = $user;
        $passwd_cache_dir  = '/var/cpanel/@pwcache';
        $cache_uid         = 0;
        $cache_gid         = 0;
        $maildir           = "$homedir/mail" . $maibox_path_addition;
        $mail_base_dir     = "$homedir/mail";
        $address           = $user . '@' . ( $hostname || 'localhost' );
        $passwd_file_key   = $user;

        # Don't look it up if we know it can't be a cpuser (like cpanel-ccs).
        # Return empty ref instead of warning.
        $cpuser_ref = {};
        if ( !Cpanel::Validate::Username::Core::reserved_username_check($user) ) {
            $cpuser_ref = Cpanel::Config::LoadCpUserFile::load($user);
        }
        $utf8mailbox = $cpuser_ref->{'UTF8MAILBOX'} ? 1 : 0;

        $mailbox_autocreate = Cpanel::Email::DisableMailboxAutocreate->is_on( $homedir, $user ) ? 0 : 1;
    }

    my $quota_file_exists = 0;
    my $read_code_ref     = sub {
        $passwd_cache_file_mtime = ( stat("$passwd_cache_dir/$passwd_cache_file") )[9];

        if ( $quota_file && -e $quota_file ) {
            $quota_file_exists = 1;
            $quota_file_mtime  = ( stat(_) )[9];
        }
        $passwd_file_mtime = ( stat($passwd_file) )[9];

        if ( $passwd_cache_file && !defined $encrypted_pass ) {    # for accttype eq mail
            my $cache_ref = Cpanel::PwFileCache::load_pw_cache(
                {
                    'passwd_cache_file'       => $passwd_cache_file,
                    'passwd_cache_dir'        => $passwd_cache_dir,
                    'passwd_cache_file_mtime' => $passwd_cache_file_mtime || 0,
                    'quota_file_mtime'        => $quota_file_mtime        || 0,
                    'passwd_file_mtime'       => $passwd_file_mtime       || 0,
                }
            );
            if ( defined $cache_ref->{'passwd'} )      { $encrypted_pass   = $cache_ref->{'passwd'}; }
            if ( defined $cache_ref->{'quota'} )       { $quota            = $cache_ref->{'quota'}; }
            if ( defined $cache_ref->{'lastchanged'} ) { $pass_change_time = $cache_ref->{'lastchanged'}; }
            if ( defined $cache_ref->{'strength'} )    { $pass_strength    = $cache_ref->{'strength'} }
        }

        if ( $quota_file_exists && !defined $quota ) {
            $quota = int( Cpanel::PwCache::PwFile::get_keyvalue_from_pwfile( $quota_file, 1, $passwd_file_key ) || 0 );
        }
        if ( !defined $encrypted_pass || !defined $pass_change_time ) {
            my $pwref = Cpanel::PwCache::PwFile::get_line_from_pwfile( $passwd_file, $passwd_file_key );
            if ( $pwref && @{$pwref} ) {
                if ( $pwref->[1] ) {
                    $encrypted_pass = $pwref->[1];
                }

                if ( $pwref->[2] ) {
                    $pass_change_time = $pwref->[2];
                }
            }
        }
    };

    my $format = 'maildir';
    {
        my $privs = ( $accttype eq 'mail' ) && ( $> == 0 );
        $privs &&= Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid );

        # When converting from mdbox -> maildir it was
        # possible for dovecot to recreate the mdbox dirs
        # while they were being deleted because there was
        # no way for Cpanel::AcctUtils::Lookup::MailUser
        # to know which format was the active one because
        # both mdbox and maildir files exist.

        # We now create a mailbox_format.cpanel file in
        # the mail account root which the mailuser lookup
        # code uses to know the active format and avoid
        # logging in the user with old mail.

        #
        # If the file is not present, we fallback to the pre
        # v62 behavior of assuming maildir (the default format)
        # unless the mdbox storage directory exists
        #
        my $mailbox_format_size = ( stat("$maildir/mailbox_format.cpanel") )[7];
        if ($mailbox_format_size) {
            if ( $mailbox_format_size == length 'mdbox' ) {
                $format = 'mdbox';
            }
            elsif ( $mailbox_format_size == length 'maildir' ) {
                $format = 'maildir';
            }
        }
        elsif ( -d "$maildir/storage" ) {
            $format = 'mdbox';
        }

        $read_code_ref->();
    }

    my $proxy_backend = _get_proxy_backend($cpuser_ref);

    # If there’s a proxy backend, then we don’t fail on a nonexistent
    # user because this lookup may be for an IMAP/POP3 connection that
    # we’re going to proxy.
    #
    if ( !length $proxy_backend && ( !length $passwd_cache_file || !length $encrypted_pass ) ) {
        die Cpanel::Exception::create( 'UserNotFound', [ name => $user ] );
    }

    my $safe_quota_file_mtime        = $quota_file_mtime        || 0;
    my $safe_passwd_file_mtime       = $passwd_file_mtime       || 0;
    my $safe_passwd_cache_file_mtime = $passwd_cache_file_mtime || 0;

    # Always keep this up to date if possible
    if ( $safe_passwd_cache_file_mtime > $now || $safe_passwd_cache_file_mtime < $safe_passwd_file_mtime || $safe_passwd_cache_file_mtime < $safe_quota_file_mtime ) {
        Cpanel::PwFileCache::save_pw_cache(
            {
                'passwd_cache_file' => $passwd_cache_file,
                'passwd_cache_dir'  => $passwd_cache_dir,
                'uid'               => ( defined $cache_uid ? $cache_uid : $uid ),
                'gid'               => ( defined $cache_gid ? $cache_gid : $gid ),
                'keys'              => {
                    'encrypted_pass' => $encrypted_pass,
                    'quota'          => $quota,
                    'realm'          => ( $accttype eq 'system' ? Cpanel::Auth::Digest::Realm::get_realm() : 'mail' ),
                    'homedir'        => $homedir,
                    'lastchanged'    => $pass_change_time,
                }
            }
        );
    }

    # Force virtual account suspension if system account is suspended.
    if ( $accttype eq 'mail' && rindex( ( $encrypted_pass // q<> ), q{*}, 0 ) == -1 && -e "/var/cpanel/suspended/${username}" ) {
        $encrypted_pass = '*LOCKED*' . ( $encrypted_pass // q<> );
    }

    $response->{'status'}    = 1;
    $response->{'statusmsg'} = 'success';
    $response->{'user_info'} = {
        'account_type'  => $accttype,
        'proxy_backend' => $proxy_backend,
        'shadow'        => {
            'user'        => $encrypted_pass,
            'domainowner' => $domainowner_encrypted_pass,
        },
        'cache' => {
            'passwd' => {
                'uid'    => $cache_uid,
                'gid'    => $cache_gid,
                'file'   => $passwd_cache_file,
                'dir'    => $passwd_cache_dir,
                'mtime'  => $passwd_cache_file_mtime,
                'exists' => ( $passwd_cache_file_mtime ? 1 : 0 ),
            },
        },
        'mailbox' => {
            'format'     => $format,
            'utf8'       => $utf8mailbox,
            'autocreate' => $mailbox_autocreate,
        },
        'passwd' => {
            'file'             => $passwd_file,
            'key'              => $passwd_file_key,
            'exists'           => 1,
            'mtime'            => $passwd_file_mtime,
            'user'             => $username,
            'uid'              => $uid,
            'gid'              => $gid,
            'homedir'          => $homedir,
            'maildir'          => $maildir,
            'address'          => $address,
            'pass_change_time' => $pass_change_time,
            'strength'         => $pass_strength,
        },
        'quota' => {
            'file'             => $quota_file,
            'exists'           => $quota_file_exists,
            'value'            => $quota,
            'mtime'            => $quota_file_mtime,
            'disk_block_limit' => ( $cpuser_ref->{'DISK_BLOCK_LIMIT'} || 0 ),
            'disk_inode_limit' => ( $cpuser_ref->{'DISK_INODE_LIMIT'} || 0 ),
        },
    };

    return $response;
}

sub _get_proxy_backend ($cpuser_ref) {
    my $proxy_backend = Cpanel::AccountProxy::Storage::get_worker_backend(
        $cpuser_ref,
        'Mail',
    );

    if ( !$proxy_backend ) {
        my $conf_hr = Cpanel::LinkedNode::Worker::GetAll::get_one_from_cpuser( 'Mail', $cpuser_ref );

        $proxy_backend = $conf_hr && $conf_hr->{'configuration'}->hostname();
    }

    return $proxy_backend;
}

1;
