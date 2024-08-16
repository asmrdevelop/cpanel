package Cpanel::Mailman::Perms;

# cpanel - Cpanel/Mailman/Perms.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#NOTE: "$list" in this module is in the "name_domain.tld" format.
#----------------------------------------------------------------------

use strict;

use Errno                   ();
use Cpanel::SafeRun::Errors ();
use Cpanel::ConfigFiles     ();

use Cpanel::Config::Httpd::Perms         ();
use Cpanel::Fcntl                        ();
use Cpanel::Mailman::Filesys             ();
use Cpanel::Mailman::NameUtils           ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::SafeFind                     ();
use Cpanel::Services::Enabled            ();
use Cpanel::PwCache                      ();
use Cpanel::Lchown                       ();
use Cpanel::Logger                       ();

our $ARCHIVE_FILE_PERMS      = 0644;
our $TOP_ARCHIVE_DIR_PERMS   = 0750;
our $INNER_ARCHIVE_DIR_PERMS = 0755;
our $DATABASE_DIR_PERMS      = 0750;
our $MBOX_FILE_PERMS         = 0660;
our $MBOX_DIR_PERMS          = 0770;

our $LISTS_DIR_PERMS           = 02775;
our $LISTS_DIR_ROOT_FILE_PERMS = 0660;
our $LISTS_DIR_FILE_PERMS      = 0664;

our $DEFAULT_LIST_GROUP = 'nobody';

# Constants
our $WARN = 1;

sub new {
    my ($class) = @_;

    my $self = {

        # Stored in object because the lookup is expensive to do
        # for every call. Note that this does not factor in whether
        # disable_cphttpd is set, but it shouldn’t matter regardless.
        'archives_load_as_user' => !Cpanel::Services::Enabled::is_enabled('httpd') || _webserver_runs_as_user(),

        'chown_func' => \&Cpanel::Lchown::lchown,
        'mailmangid' => scalar( ( Cpanel::PwCache::getpwnam('mailman') )[3] ),
        'nobodygid'  => scalar( ( Cpanel::PwCache::getpwnam('nobody') )[3] ),

        # Stored in object for convenience
        'logger'     => Cpanel::Logger->new(),
        'mailmanuid' => ( Cpanel::PwCache::getpwnam('mailman') )[2],
    };

    bless $self, $class;

    return $self;
}

# overridden in tests
#
# Note that this mock is, by design, strictly for the webserver configuration,
# which is only a part of “archives_load_as_user”.
*_webserver_runs_as_user = \*Cpanel::Config::Httpd::Perms::webserver_runs_as_user;

sub check_perms {
    require Cpanel::AccessIds;
    return Cpanel::AccessIds::do_as_user(
        'mailman',
        sub {
            return scalar Cpanel::SafeRun::Errors::saferunallerrors(
                "$Cpanel::ConfigFiles::MAILMAN_ROOT/bin/check_perms",
                '-f', '--noarchives'
            );
        }
    );

}

sub set_perms {
    my ($self) = @_;

    my $MAILMAN_ARCHIVE_DIR = Cpanel::Mailman::Filesys::MAILMAN_ARCHIVE_DIR();
    my $MAILMAN_PUBLIC_DIR  = Cpanel::Mailman::Filesys::MAILMAN_ARCHIVE_PUBLIC_DIR();
    my $MAILMAN_DIR         = Cpanel::Mailman::Filesys::MAILMAN_DIR();
    my $perm_lookup_coderef = $self->{'archives_load_as_user'} ? sub { return 0711 }   : sub { return 0710 };
    my $mailman_dir_gid     = $self->{'archives_load_as_user'} ? $self->{'mailmangid'} : $self->{'nobodygid'};

    my $set_mailman_archive_perms     = 0;
    my $set_mailman_archive_pub_perms = 0;
    Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            # Prevent direct access to the archives
            if ( $self->_set_file_perms( $MAILMAN_ARCHIVE_DIR, { 'warnings' => 0, 'perm_lookup_coderef' => $perm_lookup_coderef, 'uid' => $self->{'mailmanuid'}, 'gid' => $mailman_dir_gid } ) ) {
                $set_mailman_archive_perms = 1;
            }
            if ( $self->_set_file_perms( $MAILMAN_PUBLIC_DIR, { 'warnings' => 0, 'perm_lookup_coderef' => $perm_lookup_coderef, 'uid' => $self->{'mailmanuid'}, 'gid' => $mailman_dir_gid } ) ) {
                $set_mailman_archive_pub_perms = 1;
            }
        },
        $self->{'mailmanuid'},
        $mailman_dir_gid,
    );

    if ( !$set_mailman_archive_perms ) {
        $self->_set_file_perms( $MAILMAN_ARCHIVE_DIR, { 'warnings' => 1, 'perm_lookup_coderef' => $perm_lookup_coderef, 'uid' => $self->{'mailmanuid'}, 'gid' => $mailman_dir_gid } );
    }
    if ( !$set_mailman_archive_pub_perms ) {
        $self->_set_file_perms( $MAILMAN_PUBLIC_DIR, { 'warnings' => 1, 'perm_lookup_coderef' => $perm_lookup_coderef, 'uid' => $self->{'mailmanuid'}, 'gid' => $mailman_dir_gid } );
    }

    return 1;
}

sub set_archive_perms {
    my ($self) = @_;

    Cpanel::AcctUtils::DomainOwner::Tiny::build_domain_cache();

    my $MAILMAN_ARCHIVE_DIR = Cpanel::Mailman::Filesys::MAILMAN_ARCHIVE_DIR();

    if ( opendir( my $archives_dir, $MAILMAN_ARCHIVE_DIR ) ) {
        while ( my $list = readdir($archives_dir) ) {
            next if ( $list !~ tr/_// && $list ne 'mailman' ) || $list =~ /\.mbox$/;

            $self->set_archive_perms_for_one_list($list);

        }

        return 1;
    }

    # During installation sometimes this code path runs before
    # Mailman’s directories are created. It’s not an error state
    # if this happens; we can just ignore it.
    elsif ( !$!{'ENOENT'} ) {
        $self->{'logger'}->warn( "Failed to open: " . $MAILMAN_ARCHIVE_DIR . ": $!" );
    }

    return;
}

#This sets perms on both "$list" and "$list.mbox".
sub set_archive_perms_for_one_list {
    my ( $self, $list ) = @_;

    my $MAILMAN_ARCHIVE_DIR = Cpanel::Mailman::Filesys::MAILMAN_ARCHIVE_DIR();

    my $list_gid = $self->_get_list_gid($list);

    foreach my $dirset (
        [ "$MAILMAN_ARCHIVE_DIR/$list",      $TOP_ARCHIVE_DIR_PERMS, $INNER_ARCHIVE_DIR_PERMS, $ARCHIVE_FILE_PERMS, $list_gid ],
        [ "$MAILMAN_ARCHIVE_DIR/$list.mbox", $MBOX_DIR_PERMS,        $MBOX_DIR_PERMS,          $MBOX_FILE_PERMS,    $self->{'mailmangid'} ]
    ) {
        my ( $dir, $top_dir_perms, $inner_dir_perms, $file_perms, $dir_gid ) = @$dirset;
        next if !-d $dir;

        my ( $current_dir_perms, $current_dir_gid ) = ( stat _ )[ 2, 5 ];

        if ( $current_dir_gid != $dir_gid || ( $current_dir_perms & 07777 ) != ( $top_dir_perms & 07777 ) ) {
            $self->_set_mailman_permissions(
                $list, $dir,
                sub {
                    my ( $filename, $handle ) = @_;
                    return $top_dir_perms      if $filename eq $dir;
                    return $DATABASE_DIR_PERMS if $filename eq "$dir/database";
                    return -d $handle ? $inner_dir_perms : $file_perms;
                },
                $self->{'mailmanuid'},
                $self->{'mailmangid'}
            );

            # Correct the group ownership on the outer directory if needed
            if ( $dir_gid != $self->{'mailmangid'} ) {
                $self->_set_file_perms( $dir, { 'warnings' => 0, 'perm_lookup_coderef' => sub { return $top_dir_perms }, 'uid' => $self->{'mailmanuid'}, 'gid' => $dir_gid } );
            }
        }
    }

    return 1;
}

sub set_perms_for_one_list {
    my ( $self, $list ) = @_;

    my $basedir                   = Cpanel::Mailman::Filesys::get_list_dir($list);
    my $basedir_length_with_slash = length($basedir);

    return $self->_set_mailman_permissions(
        $list, $basedir,
        sub {
            my ( $filename, $handle ) = @_;

            my $basename = substr( $filename, $basedir_length_with_slash );

            return ( -d $handle ? $LISTS_DIR_PERMS : ( ( $basename =~ tr{/}{} ) == 1 ? $LISTS_DIR_ROOT_FILE_PERMS : $LISTS_DIR_FILE_PERMS ) );
        },
        $self->{'mailmanuid'},
        $self->{'mailmangid'},
    );
}

sub _set_file_perms {
    my ( $self, $file, $opts ) = @_;

    my $enable_warnings     = $opts->{'enable_warnings'};
    my $uid                 = $opts->{'uid'};
    my $gid                 = $opts->{'gid'};
    my $perm_lookup_coderef = $opts->{'perm_lookup_coderef'};

    if ( sysopen( my $fh, $file, Cpanel::Fcntl::or_flags(qw( O_RDONLY O_EXCL O_NOFOLLOW )) ) ) {
        if ( !-d $fh && ( stat _ )[3] > 1 ) {
            if ($enable_warnings) {
                $self->{'logger'}->warn("Could not set permissions as ($>, $)) on hard linked $file: $!");
            }

            return 0;
        }

        my ( $file_mode, $file_uid, $file_gid ) = ( stat _ )[ 2, 4, 5 ];

        my $chown_uid = ( $file_uid ne $uid ) && $uid;
        my $chown_gid = ( $file_gid ne $gid ) && $gid;

        my $chmod_perms = $perm_lookup_coderef->( $file, $fh );

        if ($>) {
            if ($chown_uid) {
                if ($enable_warnings) {
                    $self->{'logger'}->warn("Must be superuser to change user ID of $file (currently $file_uid; should be $uid)");
                }

                return 0;
            }

            my $process_egid = $);

            if ( $chown_gid && !( grep { $_ eq $gid } split m{ }, $process_egid ) ) {
                if ($enable_warnings) {
                    $self->{'logger'}->warn("Must be superuser to change group ID of $file (currently $file_gid; should be $gid)");
                }

                return 0;
            }
        }

        if ( $chown_uid || $chown_gid ) {
            chown( $chown_uid || -1, $chown_gid || -1, $fh ) || do {
                if ($enable_warnings) {
                    $self->{'logger'}->warn("Could not set ownership as ($>:$)) to ($uid:$gid) on $file: $!");
                }

                return 0;
            };
        }

        if ( ( 07777 & $file_mode ) ne ( 07777 & $chmod_perms ) ) {
            chmod( $chmod_perms, $fh ) || do {
                if ($enable_warnings) {
                    $self->{'logger'}->warn( sprintf( "chmod(%05o, $file) failed: $!", $chmod_perms ) );
                }

                return 0;
            };
        }
    }
    else {
        unless ( $!{'ELOOP'} ) {    # Symlinks are skipped on purpose
            $self->{'logger'}->warn("Could not open $file to set permissions: $!") if $enable_warnings;
            return 0;
        }
    }

    return 1;
}

# This returns the number of filesystem elements which COULD NOT BE CHANGED.
# If all elements were able to be changed, either by mailman user or root,
# return value will be 0
sub _set_mailman_permissions {
    my ( $self, $list, $path, $perm_lookup_coderef, $uid, $gid ) = @_;

    my $num_failed = Cpanel::AccessIds::ReducedPrivileges::call_as_user(
        sub {
            my $failed = 0;

            eval {
                local $SIG{'__WARN__'} = 'DEFAULT';
                local $SIG{'__DIE__'}  = 'DEFAULT';

                Cpanel::SafeFind::find(
                    {
                        'no_chdir' => 1,
                        'follow'   => 0,
                        'wanted'   => sub {
                            if ( !$self->_set_file_perms( $File::Find::name, { 'warnings' => 0, 'perm_lookup_coderef' => $perm_lookup_coderef, 'uid' => $uid, 'gid' => $gid } ) ) {
                                ++$failed;
                            }
                        },
                    },
                    $path,
                );
            };

            return $failed;
        },
        $uid,
        $gid,
    );

    if ($num_failed) {

        # We have to fix them as root (should be a one time event though)
        my $failed = 0;

        # We need to find again, because if there is a directory, the
        # previous find will not have found anything underneath it.
        Cpanel::SafeFind::find(
            {
                'no_chdir' => 1,
                'follow'   => 0,
                'wanted'   => sub {
                    if ( !$self->_set_file_perms( $File::Find::name, { 'warnings' => 1, 'perm_lookup_coderef' => $perm_lookup_coderef, 'uid' => $uid, 'gid' => $gid } ) ) {
                        ++$failed;
                    }
                }
            },
            $path,
        );
        return $failed;
    }
    return 0;
}

sub _get_list_gid {
    my ( $self, $list ) = @_;

    my $list_owner = $self->_get_list_owner($list);

    my $gid = $self->{'archives_load_as_user'} ? ( Cpanel::PwCache::getpwnam($list_owner) )[3] : $self->{'nobodygid'};

    return $gid;
}

sub _get_list_owner {
    my ( $self, $list ) = @_;

    return $DEFAULT_LIST_GROUP if $list eq 'mailman';

    my $list_domain = ( Cpanel::Mailman::NameUtils::parse_name($list) )[-1];

    $list_domain =~ s/\.mbox$//g;

    return Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $list_domain, { 'default' => $DEFAULT_LIST_GROUP } );
}

1;
