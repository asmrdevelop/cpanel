package Cpanel::Email::DisableMailboxAutocreate;

# cpanel - Cpanel/Email/DisableMailboxAutocreate.pm         Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module only concerns the stored on/off mailbox autocreate state.
# To enable or disable mailbox autocreate for a mailbox use:
#
# uapi -u koston Email disable_mailbox_autocreate email=plus@koston.org
# uapi -u koston Email disable_mailbox_autocreate email=plus@koston.org
#
# See base class for full documentation.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Config::TouchFileBase );

use Cpanel::Autodie ();

my $FILENAME = 'disable_mailbox_autocreate';

=encoding utf-8

=head1 NAME

Cpanel::Email::DisableMailboxAutocreate - Control if folders should be auto created for subaddresses by mailbox

=head1 SYNOPSIS

    use Cpanel::Email::DisableMailboxAutocreate;

    Cpanel::Email::DisableMailboxAutocreate->set_on($email)
    Cpanel::Email::DisableMailboxAutocreate->set_off($email)
    Cpanel::Email::DisableMailboxAutocreate->is_on($email)

=cut

sub _TOUCH_FILE {
    my ( $self, $user_homedir, $account ) = @_;

    my $base = $self->_get_base_dir_for_account( $user_homedir, $account );

    return $base . $FILENAME;
}

=head2 set_on($user_homedir, $email)

Creates the touchfile neded to disable mailbox autocreate
during LMTP delivery. C<$email> can be either an email account
name (e.g., C<bob@example.com>) or the system username.

=cut

sub set_on {
    my ( $self, $user_homedir, $account ) = @_;
    my $base = $self->_get_base_dir_for_account( $user_homedir, $account );
    if ( !Cpanel::Autodie::exists($base) ) {
        require Cpanel::Mkdir;
        require Cpanel::Email::Perms;
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $base, $Cpanel::Email::Perms::MAILDIR_PERMS );
    }
    return $self->SUPER::set_on( $user_homedir, $account );
}

my %basedir_cache;

sub _get_base_dir_for_account {
    my ( $self, $user_homedir, $account ) = @_;

    return $basedir_cache{$user_homedir}{$account} //= do {
        my ( $login, $domain, $extra ) = split m<@>, $account;

        if ( ( $account =~ tr</><> ) || length($extra) ) {
            die "Invalid email account: “$account”";
        }

        my $base = "$user_homedir/etc/";

        if ( length $domain ) {
            $base .= "$domain/$login/";
        }

        $base;
    };
}

1;
