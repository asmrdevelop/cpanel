package Whostmgr::Email::Action;

# cpanel - Whostmgr/Email/Action.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Email ();
use Try::Tiny;

=encoding utf-8

=head1 NAME

Whostmgr::Email::Action - Run an action on each of a user's email accounts

=head1 SYNOPSIS

    use Whostmgr::Email::Action;

    return Whostmgr::Email::Action::do_with_each_mail_account(
        $user,
        sub {
            my (@email_accounts) = @_;
            return Cpanel::Dovecot::Utils::flush_auth_caches(@email_accounts);
        },
        $BATCH_SIZE
    );

=cut

=head2 do_with_each_mail_account($user,$coderef,$batch_size)

Call the coderef for each of the user's email accounts (including the
system email account) with the specified batch size.

=cut

sub do_with_each_mail_account {
    my ( $user, $coderef, $batch_size ) = @_;

    my $email_accts = Whostmgr::Email::list_pops_for($user);
    unshift @$email_accts, $user;
    $batch_size ||= 1;
    my $ok_count = 0;
    while ( my @accounts = splice( @$email_accts, 0, $batch_size ) ) {
        try {
            $coderef->(@accounts);
            $ok_count += scalar @accounts;
        }
        catch {
            # A user may not actually exist
            local $@ = $_;
            warn;
        };
    }
    return $ok_count;

}

1;
