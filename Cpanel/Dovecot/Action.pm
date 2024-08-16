package Cpanel::Dovecot::Action;

# cpanel - Cpanel/Dovecot/Action.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Email::Action ();
use Cpanel::ServerTasks     ();
use Try::Tiny;

our $BATCH_SIZE = 256;

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::Action - Perform dovecot actions on email accounts

=head1 SYNOPSIS

    use Cpanel::Dovecot::Action ();

    my $flushed_count = Cpanel::Dovecot::Action::flush_all_auth_caches_for_user('bob');

=cut

=head2 flush_all_auth_caches_for_user($user)

Flushes the dovecot authentication cache for every email account the user owns,
including the user’s system email account.

Currently we do 256 at a time.

=cut

sub flush_all_auth_caches_for_user {
    my ($user) = @_;

    require Cpanel::Dovecot::FlushAuthQueue::Adder;
    Whostmgr::Email::Action::do_with_each_mail_account(
        $user,
        sub {
            my (@accounts) = @_;
            foreach my $email_account (@accounts) {
                Cpanel::Dovecot::FlushAuthQueue::Adder->add($email_account);
            }
        },
        $BATCH_SIZE
    );

    return Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 10, 'flush_dovecot_auth_cache' );

}

1;
