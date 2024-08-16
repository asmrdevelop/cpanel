#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/dovecot.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::dovecot;

use strict;
use warnings;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception ();

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::dovecot - dovecot admin module

=head1 SYNOPSIS

    use Cpanel::AdminBin::Call ()
    my $adminbin_return = Cpanel::AdminBin::Call::call( 'Cpanel', 'multilang', 'SET_VHOST_LANG_PACKAGE', $vhost, $lang, $package );

=head1 DESCRIPTION

Allows cPanel and Webmail users to access root only dovecot functions safely. Such as reindexing their mailbox.

=cut

sub _actions {
    return qw(FTS_RESCAN_MAILBOX);
}

=head2 FTS_RESCAN_MAILBOX

Wrapper to call fts_rescan_mailbox

=over 2

=item Input

=over 3

=item C<HASHREF>

    $args - function expects a hashref containing an "account" key

=back

=item Output

=over 3

=item C<NONE>

    Returns the results of Cpanel::Dovecot::Utils::fts_rescan_mailbox which is currently nothing.

=back

=back

=cut

sub FTS_RESCAN_MAILBOX {
    my ( $self, $args ) = @_;
    my $caller_username = $self->get_caller_username();

    require Cpanel::AcctUtils::Lookup::MailUser::Exists;
    if ( !Cpanel::AcctUtils::Lookup::MailUser::Exists::does_mail_user_exist( $args->{'account'} ) ) {
        die Cpanel::Exception::create( "Email::AccountNotFound", [ name => $args->{'account'} ] );
    }

    require Cpanel::Services::Enabled;

    if ( !Cpanel::Services::Enabled::is_enabled('cpanel-dovecot-solr') ) {
        die Cpanel::Exception::create( 'Services::Disabled', [ 'service' => 'cpanel-dovecot-solr' ] );
    }

    require Cpanel::AccessControl;
    if ( Cpanel::AccessControl::user_has_access_to_account( $caller_username, $args->{'account'} ) ) {
        require Cpanel::Dovecot::FTSRescanQueue::Adder;
        require Cpanel::ServerTasks;
        Cpanel::Dovecot::FTSRescanQueue::Adder->add( $args->{'account'} );
        return Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 10, 'fts_rescan_mailbox' );
    }
    else {
        die Cpanel::Exception->create( "The user “[_1]” does not have access to the account “[_2]”.", [ $caller_username, $args->{'account'} ] );
    }

    return;
}

1;
