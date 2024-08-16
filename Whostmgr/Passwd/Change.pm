package Whostmgr::Passwd::Change;

# cpanel - Whostmgr/Passwd/Change.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings                  ();
use Cpanel::LoadModule        ();
use Cpanel::Debug             ();
use Cpanel::ChangePasswd      ();
use Cpanel::Exception         ();
use Cpanel::Locale            ();
use Cpanel::PwCache::Clear    ();
use Whostmgr::AcctInfo::Owner ();
use Whostmgr::ACLS            ();

use Try::Tiny;

my $locale;

=encoding utf-8

=head1 NAME

Whostmgr::Passwd::Change - Tools for changing a user's password

=head1 SYNOPSIS

    use Whostmgr::Passwd::Change;

    Whostmgr::Passwd::Change::passwd('bob','strongpassword',{'mysql'=>1,'digest'=>1});

=cut

=head2 passwd($user,$pass,$optional_services)

Change a user's password

=over 2

=item Input

=over 3

=item C<SCALAR>

    The username to change the password for

=item C<SCALAR>

    The new password

=item C<HASHREF>

    A hashref of additional service passwords to be changed.

    The key is the service to change and the value should always be 1.

    Example:
    {
      'mysql'  => 1,
      'digest' => 1,
    }

=back

=item Output (Array Context)

=over 3

=item C<SCALAR>

    The status of the password change (0 or 1)

=item C<SCALAR>

    The status message for the password change

=item C<SCALAR>

    Any errors from the password change

=item C<ARRAYREF>

    An arrayref of the services the password was changed for.

=back

=item Output (Scalar Context)

=over 3

=item C<SCALAR>

    The status of the password change (0 or 1)

=back

=back

=cut

sub passwd {
    my ( $user, $pass, $optional_services, $xtra_opts ) = @_;

    die "Invalid format for xtra_opts" if defined $xtra_opts && ref $xtra_opts ne 'HASH';

    Cpanel::LoadModule::load_perl_module('Cpanel::Hulk::Admin::Utils');

    if ( !defined $user || !$user ) {
        return wantarray ? ( 0, _locale()->maketext('No account was specified.') ) : _locale()->maketext('No account was specified.');
    }
    elsif ( !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $user ) ) {
        my $msg = _locale()->maketext( 'You are not permitted to change the password for “[_1]” because you are not the owner of this account.', $user );

        return wantarray ? ( 0, $msg, $msg, [] ) : 0;
    }
    else {
        my @result = Cpanel::ChangePasswd::change_password(
            'new_password'      => $pass,
            'user'              => $user,
            'optional_services' => $optional_services,
            'ip'                => $ENV{'REMOTE_ADDR'},
            'origin'            => 'whm',
            'initiator'         => $ENV{'REMOTE_USER'},
            %{$xtra_opts}{'password_strength_check'},
        );

        Whostmgr::ACLS::init_acls();
        if ( Whostmgr::ACLS::hasroot() ) {
            try {
                Cpanel::Hulk::Admin::Utils::clear_bad_logins_and_temp_bans_for_user($user);
            }
            catch {
                my $err = $_;
                Cpanel::Debug::log_warn( "There was an error clearing bad logins and temp bans for the user '$user': " . Cpanel::Exception::get_string($err) );
            };
        }

        Cpanel::PwCache::Clear::clear_global_cache();

        return wantarray ? @result : $result[0];
    }
}

sub _locale {
    return ( $locale ||= Cpanel::Locale->get_handle() );
}

1;
