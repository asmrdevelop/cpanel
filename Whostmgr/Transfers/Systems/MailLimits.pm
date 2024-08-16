package Whostmgr::Transfers::Systems::MailLimits;

# cpanel - Whostmgr/Transfers/Systems/MailLimits.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::MailLimits

=head1 SYNOPSIS

N/A

=head1 DESCRIPTION

This module exists to be called from the account restore system.
It should not be invoked directly except from that framework.

It restores the user’s outgoing email holds and suspensions.
Its restricted and unrestricted modes are identical.

=head1 METHODS

=cut

use strict;
use warnings;

use parent qw(Whostmgr::Transfers::SystemsBase::Distributable::Mail);

use Cpanel::Email::Accounts::Paths ();
use Cpanel::JSON                   ();
use Cpanel::LoadFile               ();
use Whostmgr::Accounts::Email      ();

use Try::Tiny;

use constant { get_restricted_available => 1 };

=head2 I<OBJ>->get_summary()

POD for cplint. Don’t call this directly.

=cut

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This restores any holds or suspensions on outgoing messages for a user’s email accounts.') ];
}

sub get_prereq {
    return ['Mail'];
}

=head2 I<OBJ>->restricted_restore()

POD for cplint. Don’t call this directly.

=cut

sub restricted_restore {
    my ($self) = @_;

    $self->start_action("Restoring mail limits (if any)");

    my $user = $self->newuser();

    my $extractdir = $self->extractdir();
    my $file       = "$extractdir/$Cpanel::Email::Accounts::Paths::EMAIL_SUSPENSIONS_FILE_NAME";

    my $limits_str = Cpanel::LoadFile::load_if_exists($file);

    if ($limits_str) {

        my $limits_ref = Cpanel::JSON::Load($limits_str);

        foreach my $domain ( keys %$limits_ref ) {
            foreach my $account ( keys %{ $limits_ref->{$domain}{'suspended'} } ) {
                try {
                    Whostmgr::Accounts::Email::suspend_mailuser_outgoing_email( 'user' => $user, 'email' => "$account\@$domain" );
                }
                catch {
                    $self->warn( $self->_locale()->maketext( "The system was unable to restore the outgoing mail suspension for “[_1]” because of an error: [_2]", $account, $_ ) );
                };
            }
            foreach my $account ( keys %{ $limits_ref->{$domain}{'hold'} } ) {
                try {
                    Whostmgr::Accounts::Email::hold_mailuser_outgoing_email( 'user' => $user, 'email' => "$account\@$domain" );
                }
                catch {
                    $self->warn( $self->_locale()->maketext( "The system was unable to restore the outgoing mail hold for “[_1]” because of an error: [_2]", $account, $_ ) );
                };
            }
        }

    }

    return 1;
}

*unrestricted_restore = \&restricted_restore;

1;
