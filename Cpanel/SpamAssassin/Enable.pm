package Cpanel::SpamAssassin::Enable;

# cpanel - Cpanel/SpamAssassin/Enable.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::SpamAssassin::Enable

=head1 SYNOPSIS

    use Cpanel::SpamAssassin::Enable ();

    Cpanel::SpamAssassin::Enable::enable('someuser');
    Cpanel::SpamAssassin::Enable::disable('someuser');
    if ( Cpanel::SpamAssassin::Enable::is_enabled('some_user')) {
        say 'Apache SpamAssassin™ is enabled';
    }

=head1 DESCRIPTION

This is a small set of functions for manipulating the
F<.spamassassinenable> file in a user's home directory, thus indicating
to cPanel and WHM's Apache SpamAssassin™ support that the software is
enabled.

=cut

use strict;
use warnings;
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::FileUtils::TouchFile         ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::PwCache                      ();
use Cpanel::Umask                        ();

use Try::Tiny;

our $_SPAMBOX_TOUCHFILE_NAME = ".spamassassinboxenable";

=head1 SUBROUTINES

=head2 enable

Given a user name, enables Apache SpamAssassin™ for that user by
creating the F<.spamassassinenable> touch file in the user's home
directory and ensuring the directory also contains a F<tmp> directory.

Returns 1 if the touch file was successfully created, and 0 otherwise.

=cut

sub enable {
    my $user_name = shift;
    my ( $uid, $gid, $home_dir ) =
      ( Cpanel::PwCache::getpwnam_noshadow($user_name) )[ 2, 3, 7 ];

    return 0 if not defined $home_dir;
    my $sa_touchfile = "$home_dir/.spamassassinenable";
    my $tmpdir       = "$home_dir/tmp";

    my $privs_obj = _drop_privs_if_needed( $uid, $gid );

    return _enable_files( $home_dir, $sa_touchfile, $tmpdir );
}

sub _enable_files {
    my ( $home_dir, $touchfile, $tmpdir ) = @_;
    my $result = 0;

    if ( not -e $touchfile ) {
        Cpanel::FileUtils::TouchFile::touchfile($touchfile);
        $result = 1;
    }

    if ( not -e $tmpdir ) {
        Cpanel::SafeDir::MK::safemkdir( $tmpdir, '0755' );
    }
    if ( not -d "$home_dir/.spamassassin" ) {
        Cpanel::SafeDir::MK::safemkdir( "$home_dir/.spamassassin", '0700' ) or die "Failed to create $home_dir/.spamassassin: $!";
    }

    if ( not -e "$home_dir/.spamassassin/user_prefs" ) {
        my @warnings;
        eval {
            require Mail::SpamAssassin;

            # send SpamAssassin's warnings to the void
            local $SIG{__WARN__} = sub { push @warnings, $_[0]; };
            local $ENV{MAIL}     = "$home_dir/mail/inbox";

            my $umask_obj = Cpanel::Umask->new(0077);
            Mail::SpamAssassin->new->create_default_prefs(
                "$home_dir/.spamassassin/user_prefs",
            );
        };
        if ( !-e "$home_dir/.spamassassin/user_prefs" ) {
            my $first_error = shift @warnings;
            foreach (@warnings) {
                local $@ = $_;
                warn;
            }
            if ($first_error) {
                local $@ = $first_error;
                die;
            }
            else {
                die "Failed to create($home_dir/.spamassassin/user_prefs): unknown error";
            }
        }
    }
    return $result;
}

=head2 disable

Given a user name, disables Apache SpamAssassin™ for that user by
deleting the F<.spamassassinenable> touch file in the user's home
directory.

Returns 1 if the touch file was successfully removed, or 0 otherwise.

=cut

sub disable {
    my $sa_touchfile = Cpanel::PwCache::gethomedir(shift) . '/.spamassassinenable';
    return 0 if not -e $sa_touchfile;
    return unlink $sa_touchfile;
}

=head2 is_enabled

Given a user name, tests for the existence of the F<.spamassassinenable>
touch file in the user's home directory.

=cut

sub is_enabled {
    return -e Cpanel::PwCache::gethomedir(shift) . '/.spamassassinenable'
      ? 1
      : 0;
}

=head2 enable_spam_box

Given a user name, enables Spam Box for that user by creating
the F<.spamassassinboxenable> touch file in the user's home
directory.

=over 2

=item Input

=over 3

=item C<SCALAR>

The user name to enable spam box for

=back

=item Output

Returns truthy if the spam box is enabled, falsey if it was already enabled.

=back

=cut

sub enable_spam_box {

    my ($user) = @_;

    _check_username($user);

    my ( $home_dir, $uid, $gid ) = _get_stat($user);

    my $touchfile = "$home_dir/$_SPAMBOX_TOUCHFILE_NAME";
    my $privs_obj = _drop_privs_if_needed( $uid, $gid );

    my $created;
    require Cpanel::Autodie;
    require Cpanel::Fcntl;
    try {
        Cpanel::Autodie::sysopen(
            my $fh,    ## no critic qw(ProhibitUnusedVariables) fh unneeded after open, but cannot be undefined for sysopen
            $touchfile,
            Cpanel::Fcntl::or_flags(qw( O_CREAT  O_EXCL )),
            0644
        );
        $created = 1;
    }
    catch {
        if ( !try { $_->error_name() eq 'EEXIST' } ) {
            local $@ = $_;
            die;
        }

        $created = 0;
    };

    return $created;
}

=head2 disable_spam_box

Given a user name, disables Spam Box for that user by deleting
the F<.spamassassinboxenable> touch file in the user's home
directory.

=over 2

=item Input

=over 3

=item C<SCALAR>

The user name to disable spam box for

=back

=item Output

Returns truthy if the spam box is disabled, falsey if it was already disabled.

=back

=cut

sub disable_spam_box {

    my ($user) = @_;

    _check_username($user);

    my ( $home_dir, $uid, $gid ) = _get_stat($user);

    my $touchfile = "$home_dir/$_SPAMBOX_TOUCHFILE_NAME";

    # NB: A privs drop is unnecessary here because we’re only
    # altering the user’s homedir, which they don’t directly
    # control, so there’s no way for the user to “trick” a
    # privileged process into unlinking something other than
    # the intended filesystem node.

    require Cpanel::Autodie;
    return Cpanel::Autodie::unlink_if_exists($touchfile);
}

=head2 is_spam_box_enabled

Given a user name, tests for the existence of the F<.spamassassinboxenable>
touch file in the user's home directory.

=cut

=over 2

=item Input

=over 3

=item C<SCALAR>

The user name to check

=back

=item Output

Returns truthy if the spam box touch file exists, falsy if not.

=back

=cut

sub is_spam_box_enabled {
    my ($user) = @_;

    _check_username($user);

    my ($home_dir) = _get_stat($user);

    my $touchfile = "$home_dir/$_SPAMBOX_TOUCHFILE_NAME";

    require Cpanel::Autodie;
    return Cpanel::Autodie::exists($touchfile);
}

#----------------------------------------------------------------------

sub _drop_privs_if_needed {
    my ( $uid, $gid ) = @_;

    if ( not $> and $uid and $gid ) {

        require Cpanel::AccessIds::ReducedPrivileges;
        return Cpanel::AccessIds::ReducedPrivileges->new( $uid, $gid );
    }

    return;
}

sub _check_username {
    if ( !$_[0] ) {

        require Cpanel::Exception;

        # Users should never see this error.
        die Cpanel::Exception::create_raw( 'MissingParameter', "You must specify a user name." );
    }

    return;
}

sub _get_stat {
    my ($username) = @_;

    require Cpanel::PwCache;
    my ( $uid, $gid, $home_dir ) = ( Cpanel::PwCache::getpwnam_noshadow($username) )[ 2, 3, 7 ];

    die Cpanel::Exception->create( "The system could not determine a home directory for the user “[_1]”.", [$username] ) if !$home_dir;

    return ( $home_dir, $uid, $gid );
}

1;
