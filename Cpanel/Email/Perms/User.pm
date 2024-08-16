package Cpanel::Email::Perms::User;

# cpanel - Cpanel/Email/Perms/User.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module is here to ensure that Exim can deliver mail.
# For a fuller variant on this behavior, see scripts/mailperm.
#----------------------------------------------------------------------

use cPstrict;

use Errno qw[ENOENT EACCES];
use Try::Tiny;

use Cpanel::PwCache                      ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::Autodie                      ();
use Cpanel::FileUtils::Dir               ();
use Cpanel::Fcntl                        ();
use Cpanel::Email::Perms                 ();
use Cpanel::Validate::Domain             ();
use Cpanel::SV                           ();

#This is always local()ed within this module when set.
our $_DROPPED_PRIVS;

# %PERMS format:
# TYPE => relative_file => [ PERMS, GROUP_CONST, CREATE_CONST ];
my %PERMS = (
    'MAIN' => {

        #“mail” is a Maildir structure.
        #http://wiki.dovecot.org/MailboxFormat/Maildir
        'mail' => [
            $Cpanel::Email::Perms::MAILDIR_PERMS,
            $Cpanel::Email::Perms::NEEDS_GID_USER,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
        'mail/cur' => [
            $Cpanel::Email::Perms::MAILDIR_PERMS,
            $Cpanel::Email::Perms::NEEDS_GID_USER,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
        'mail/new' => [
            $Cpanel::Email::Perms::MAILDIR_PERMS,
            $Cpanel::Email::Perms::NEEDS_GID_USER,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
        'mail/tmp' => [
            $Cpanel::Email::Perms::MAILDIR_PERMS,
            $Cpanel::Email::Perms::NEEDS_GID_USER,
            $Cpanel::Email::Perms::CREATE_NO,
        ],

        #“etc” is a cPanel-originated directory, which can include
        #authentication and quota information that Exim needs
        #to read.
        'etc' => [
            $Cpanel::Email::Perms::ETC_PERMS,
            $Cpanel::Email::Perms::NEEDS_GID_MAIL,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
    },
    'DOMAIN' => {
        'mail/%domain%' => [
            $Cpanel::Email::Perms::MAILDIR_PERMS,
            $Cpanel::Email::Perms::NEEDS_GID_USER,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
        'etc/%domain%' => [
            $Cpanel::Email::Perms::ETC_PERMS,
            $Cpanel::Email::Perms::NEEDS_GID_MAIL,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
        'etc/%domain%/passwd' => [
            0640,
            $Cpanel::Email::Perms::NEEDS_GID_MAIL,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
        'etc/%domain%/passwd,v' => [
            0640,
            $Cpanel::Email::Perms::NEEDS_GID_MAIL,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
        'etc/%domain%/quota' => [
            0640,
            $Cpanel::Email::Perms::NEEDS_GID_MAIL,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
        'etc/%domain%/quota,v' => [
            0640,
            $Cpanel::Email::Perms::NEEDS_GID_MAIL,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
        'etc/%domain%/shadow' => [
            0640,
            $Cpanel::Email::Perms::NEEDS_GID_MAIL_IF_NOT_EXTERNAL_AUTH,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
        'etc/%domain%/shadow,v' => [
            0640,
            $Cpanel::Email::Perms::NEEDS_GID_MAIL_IF_NOT_EXTERNAL_AUTH,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
    },
    'USER' => {

        #SMTP needs to be able to read “maildirsize”.
        #Dovecot changes the directory to user:user ownership, though,
        #so we have to set the world-exec bit on the directory.

        'mail/%domain%/%user%' => [
            $Cpanel::Email::Perms::MAILDIR_PERMS,
            $Cpanel::Email::Perms::NEEDS_GID_USER,
            $Cpanel::Email::Perms::CREATE_NO,
        ],
    },
);

sub _verify_euid_and_ruid {
    die "Must not run as root!"                if !$>;
    die "Must be able to setuid back to root!" if $<;

    return;
}

#NOTE: The return from this is meant to go into $_DROPPED_PRIVS,
#which should be local()ed!!
sub _get_privs_obj_for_homedir {
    my ($homedir) = @_;

    my $target_uid = ( Cpanel::Autodie::stat($homedir) )[4];

    return Cpanel::AccessIds::ReducedPrivileges->new(
        $target_uid,
        scalar( ( Cpanel::PwCache::getpwuid_noshadow($target_uid) )[3] ),
        _mailgid(),
    );
}

sub ensure_user_domain_main_perms {
    my ( $homedir, $domain, $user ) = @_;

    local $_DROPPED_PRIVS = _get_privs_obj_for_homedir($homedir) if !$_DROPPED_PRIVS;
    _ensure_perms( 'MAIN',   $homedir );
    _ensure_perms( 'DOMAIN', $homedir, $domain );
    _ensure_perms( 'USER',   $homedir, $domain, $user );
    return 1;
}

#Checks the MAIN items in %PERMS above.
sub ensure_main_perms {
    my ($homedir) = @_;

    local $_DROPPED_PRIVS = _get_privs_obj_for_homedir($homedir) if !$_DROPPED_PRIVS;

    return _ensure_perms( 'MAIN', $homedir );
}

#Checks the DOMAIN items in %PERMS above.
sub ensure_domain_perms {
    my ( $homedir, $domain ) = @_;

    local $_DROPPED_PRIVS = _get_privs_obj_for_homedir($homedir) if !$_DROPPED_PRIVS;

    return _ensure_perms( 'DOMAIN', $homedir, $domain );
}

#Checks the USER items in %PERMS above.
sub ensure_user_perms {
    my ( $homedir, $domain, $user ) = @_;

    local $_DROPPED_PRIVS = _get_privs_obj_for_homedir($homedir) if !$_DROPPED_PRIVS;

    return _ensure_perms( 'USER', $homedir, $domain, $user );
}

sub ensure_all_perms {
    my $homedir = shift;

    die "Need homedir!" if !$homedir;

    local $_DROPPED_PRIVS = _get_privs_obj_for_homedir($homedir) if !$_DROPPED_PRIVS;

    ensure_main_perms($homedir);

    my $nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes_if_exists("$homedir/mail");

    if ($nodes_ar) {
        for my $domain (@$nodes_ar) {
            next if !Cpanel::Validate::Domain::is_valid_cpanel_domain($domain);

            next if !-d "$homedir/mail/$domain";

            ensure_domain_perms( $homedir, $domain );

            for my $user ( @{ Cpanel::FileUtils::Dir::get_directory_nodes("$homedir/mail/$domain") } ) {
                next if $user =~ m<^\.>;
                next if $user eq '@pwcache';
                next if $user eq 'boxtrapper';

                next if !-d "$homedir/mail/$domain/$user";

                ensure_user_perms( $homedir, $domain, $user );
            }
        }
    }

    return;
}

sub _ensure_perms {
    my ( $key, $homedir, $domain, $user ) = @_;

    _verify_euid_and_ruid();

    Cpanel::SV::untaint($homedir);

    foreach my $path ( keys %{ $PERMS{$key} } ) {
        my $perm_keys = $PERMS{$key}->{$path};

        if ( length $domain ) {
            $path =~ s<%domain%><$domain>g;

            if ( length $user ) {
                $path =~ s<%user%><$user>g;
            }
        }

        $path = $homedir . '/' . $path;
        Cpanel::SV::untaint($path);

        _set_perms( $path, $perm_keys );
    }
    return;
}

#XXX: It is VERY IMPORTANT that we NOT run this function as root!!
#Otherwise we could inadvertently open the server to filesystem link attacks.
sub _set_perms {
    my ( $path, $perm_keys ) = @_;

    my $file;
    local $!;

    # Autodie turned out to be too expensive here
    if ( !open( $file, '<', $path ) ) {
        my $error = $!;
        undef $file;
        if ( $error == ENOENT ) {
            if ( $perm_keys->[$Cpanel::Email::Perms::FIELD_CREATE] ) {    # Create ok
                Cpanel::Autodie::sysopen(
                    $file,
                    $path,
                    Cpanel::Fcntl::or_flags(qw(O_WRONLY O_CREAT O_EXCL)),
                    $perm_keys->[$Cpanel::Email::Perms::FIELD_PERMS],
                );

                _print_if_verbose("Created $path");
            }
        }
        elsif ( $error == EACCES ) {

            # We can't open the file since we don't have read permission.
            # Operate on the file name instead of a file handle.
            $file = $path;
        }
        else {
            warn "Failed to open($path): $!";
        }
    }

    return if !$file;

    my ( $mode, $nlink, $uid, $gid ) = ( stat $file )[ 2, 3, 4, 5 ] or do {
        warn "Failed to stat($path): $!";
        return;
    };

    if ( !( -d _ ) && $nlink > 1 ) {
        warn "Skipping multiply-linked filesystem node $path!";
        return;
    }

    $mode &= 07777;

    my $target_mode = $perm_keys->[$Cpanel::Email::Perms::FIELD_PERMS];

    my $target_gid;
    my $mail_gid_setting = $perm_keys->[$Cpanel::Email::Perms::FIELD_GID];

    if ( $mail_gid_setting == $Cpanel::Email::Perms::NEEDS_GID_MAIL ) {
        $target_gid = _mailgid();
    }
    else {
        $target_gid = ( split( / /, $) ) )[0];    #i.e. effective group
    }

    if ( ( $gid || 0 ) != $target_gid ) {
        if ( chown -1, $target_gid, $file ) {
            _print_if_verbose("Fixed owner-group of $path: was “$gid”, now “$target_gid”");
        }
        else {
            my $err             = $!;
            my $target_gid_name = ( getgrgid $target_gid )[0];
            warn "Failed to chown “$path” to group “$target_gid_name”: $err";
        }
    }

    if ( $mode != $target_mode ) {
        if ( chmod( $target_mode, $file ) ) {
            _print_if_verbose( sprintf "Fixed permissions on $path: was (0%o), now (0%o)", $mode, $target_mode );
        }
        else {
            warn sprintf "Failed to chmod “$path” to 0%o permissions: $!", $target_mode;
        }
    }

    return;
}

sub _print_if_verbose {
    my ($msg) = @_;

    return unless $Cpanel::Email::Perms::VERBOSE;
    return print("$msg\n");
}

my $_mailgid;

sub _mailgid {
    return $_mailgid ||= ( Cpanel::PwCache::getpwnam('mail') )[3];
}

1;
