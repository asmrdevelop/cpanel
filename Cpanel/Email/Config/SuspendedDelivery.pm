package Cpanel::Email::Config::SuspendedDelivery;

# cpanel - Cpanel/Email/Config/SuspendedDelivery.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::Email::Config::SuspendedDelivery - suspended account email handling

=head1 DESCRIPTION

This module contains functions to inspect and configure the email delivery
behavior for suspended cPanel accounts.

=head1 SYNOPSIS

 use Cpanel::Email::Config::SuspendedDelivery ();

 print "Current setting is: " . Cpanel::Email::Config::SuspendedDelivery::current_setting() . "\n";

 print "Recommended setting is: " . Cpanel::Email::Config::SuspendedDelivery::recommended_setting() . "\n";

 print "Setting configuration to discard incoming email for suspended accounts.\n";
 Cpanel::Email::Config::SuspendedDelivery::set_value(Cpanel::Email::Config::SuspendedDelivery::DISCARD);

=head1 CONSTANTS

=head2 Setting constants

=over 4

=item C<BLOCK>

RFC compliant SMTP-time rejection of incoming messages to suspended accounts.
This setting informs the client system that the account is disabled rather than invalid.

The client system will not reattempt delivery later.

=item C<BOUNCE>

SMTP-time rejection of incoming messages to suspended accounts using temporary failure
response codes.

This behaves similarly to greylisting except that the messages are not accepted until
the recipient cPanel account is unsuspended.

=item C<DEFAULT>

This setting is equivalent to the current C<recommended_setting()> for the purposes of
the C<set_value()> function. In other locations, this setting indicates no specific
configuration option has been selected.

=item C<DELIVER>

Email to suspended accounts is delivered normally.

=item C<DISCARD>

Email to suspended accounts is accepted at SMTP-time and discarded by the server.

=item C<QUEUE>

Email to suspended accounts is accepted at SMTP-time and held in the Exim mail queue
while the account remains suspended. Exim reattempts delivery of the message at
regular intervals.

If a queued message is not eventually delivered, it will be returned to the
envelope sender address according to the configured Exim retry settings. By default
on cPanel & WHM systems, this will bounce the message back after 4 days and 8 hours.

=back

=head2 C<ACTION_*>

The C<ACTION_*> constants contain a string with the  Exim redirection list version of each
setting for email handling. All data storage uses this format.

=over 4

=item C<ACTION_BLOCK>

=item C<ACTION_BOUNCE>

=item C<ACTION_DEFAULT>

=item C<ACTION_DELIVER>

=item C<ACTION_DISCARD>

=item C<ACTION_QUEUE>

=back


=head2 C<LABEL_*>

The C<LABEL_*> constants contain a text version of the matching C<ACTION_*> constants.
For more information about the behavior of these settings, refer to the L<ACTION_*>
section.

=over 4

=item C<LABEL_BLOCK>

=item C<LABEL_BOUNCE>

=item C<LABEL_DEFAULT>

=item C<LABEL_DELIVER>

=item C<LABEL_DISCARD>

=item C<LABEL_QUEUE>

=back

=cut

use constant BOUNCE  => 'bounce';
use constant BLOCK   => 'block';
use constant QUEUE   => 'queue';
use constant DISCARD => 'discard';
use constant DELIVER => 'deliver';
use constant DEFAULT => 'default';

use constant ACTION_BOUNCE  => 'defer';
use constant ACTION_BLOCK   => 'fail';
use constant ACTION_QUEUE   => 'queue';
use constant ACTION_DISCARD => 'blackhole';
use constant ACTION_DELIVER => 'unknown';
use constant ACTION_DEFAULT => 'default';

use constant LABEL_BOUNCE  => 'Reject messages at SMTP time with a temporary failure';
use constant LABEL_BLOCK   => 'Reject messages at SMTP time';
use constant LABEL_QUEUE   => 'Accept and queue messages';
use constant LABEL_DISCARD => 'Accept and discard messages';
use constant LABEL_DELIVER => 'Deliver messages normally';
use constant LABEL_DEFAULT => 'Use server default';

=head1 FUNCTIONS

=cut

our %SUSPENDED_ACTION_MAPPING = (
    BOUNCE()  => ACTION_BOUNCE(),
    BLOCK()   => ACTION_BLOCK(),
    QUEUE()   => ACTION_QUEUE(),
    DISCARD() => ACTION_DISCARD(),
    DELIVER() => ACTION_DELIVER(),
    DEFAULT() => ACTION_DEFAULT(),
);

our %SUSPENDED_LABEL_MAPPING = (
    BOUNCE()  => LABEL_BOUNCE(),
    BLOCK()   => LABEL_BLOCK(),
    QUEUE()   => LABEL_QUEUE(),
    DISCARD() => LABEL_DISCARD(),
    DELIVER() => LABEL_DELIVER(),
    DEFAULT() => LABEL_DEFAULT(),
);

our %SUSPENDED_ACTION_MESSAGE = (
    ACTION_BLOCK()   => '525 5.7.13 Disabled recipient address',
    ACTION_BOUNCE()  => 'Disabled recipient address',
    ACTION_QUEUE()   => 'Disabled recipient address',
    ACTION_DISCARD() => 'Disabled recipient address (discarding)',
    ACTION_DELIVER() => '',
    ACTION_DEFAULT() => '',
);

=head2 C<suspended_list_path()>

This function returns the path to the suspended account redirection list.

=head3 Arguments

None

=head3 Returns

A string containing the full filesystem path.

=head3 Throws

No exceptions are thrown.

=cut

sub suspended_list_path {
    return '/etc/exim_suspended_list';
}

=head2 C<recommended_setting()>

This function provides access to the cPanel default setting that is recommended
and used for new installations.

=head3 Arguments

None

=head3 Returns

A constant string containing the recommended default setting.

=head3 Throws

No exceptions are thrown.

=cut

sub recommended_setting {
    return QUEUE();
}

=head2 C<upgrade_setting()>

This function provides access to the cPanel default setting that is recommended
and used for upgrades.

=head3 Arguments

None

=head3 Returns

A constant string containing the recommended upgrade setting.

=head3 Throws

No exceptions are thrown.

=cut

sub upgrade_setting {
    return DELIVER();
}

=head2 C<current_setting()>

This function returns the currently configured setting. It reads the setting from the
suspended redirection list file rather than from exim.conf.localopts so that a manually
edited redirection list is presented accurately.

=head3 Arguments

None

=head3 Returns

A constant string containing the currently configured setting.

=head3 Throws

No exceptions are thrown.

=cut

sub current_setting {
    return DELIVER() unless -e suspended_list_path();

    require Cpanel::LoadFile;

    my $content_ref = Cpanel::LoadFile::loadfile_r( suspended_list_path() );
    if ( $$content_ref =~ /^\s*\*\s*:\s+:([a-z]+):/m ) {
        return get_setting($1);
    }
    return DELIVER();
}

=head2 C<get_label($setting)>

This function maps any valid setting into it's matching LABEL constant.

If the setting is not valid, undef is returned.

=cut

sub get_label {
    return $SUSPENDED_LABEL_MAPPING{ $_[0] };
}

=head2 C<get_action($setting)>

This function maps any valid setting into it's matching ACTION constant.

If the setting is not valid, undef is returned.

=cut

sub get_action {
    return $SUSPENDED_ACTION_MAPPING{ $_[0] };
}

=head2 C<get_router($setting)>

This function returns an exim router entry for any valid setting.

If the setting is not valid, undef is returned.

=cut

sub get_router {
    my ($setting) = @_;

    my $action = get_action($setting);

    return undef unless ( defined $action );

    my $message = length( $SUSPENDED_ACTION_MESSAGE{$action} ) ? " $SUSPENDED_ACTION_MESSAGE{$action}" : '';

    return ":${action}:${message}";
}

=head2 C<get_setting($setting)>

This function maps any valid C<LABEL_*>, C<ACTION_*> or router into it's equivalent setting contant.

If the setting is not a valid ACTION, LABEL, or router, undef is returned.

=cut

sub get_setting {
    my ($action_label_router) = @_;

    return undef unless ( defined $action_label_router );

    # Empty string is equivalent to an :unknown: router setting
    return DELIVER() unless ( length $action_label_router );

    if ( $action_label_router =~ /\A\s*:([a-z]+):/ ) {
        $action_label_router = $1;
    }

    return ( ( map { ( $SUSPENDED_ACTION_MAPPING{$_} eq $action_label_router || $SUSPENDED_LABEL_MAPPING{$_} eq $action_label_router ) ? $_ : () } keys %SUSPENDED_ACTION_MAPPING )[0] );
}

=head2 C<set_value($setting)>

This function applies the supplied configuration setting. It will create the
suspended redirection list if it does not exist already, and will add comments
to the redirection list explaining the settings if the list is empty.

=head3 Arguments

=over 4

=item A string containing a valid setting.

See the L<Setting constants> section for the full list of the allowed settings.

You may also use any of the C<LABEL_*> or C<ACTION_*> constants to specify the
desired setting.

=back

=head3 Returns

An integer 0 if the supplied setting is invalid.

An integer 1 if the supplied setting was applied successfully.

=head3 Throws

No exceptions are thrown directly.

This function may emit untrapped exceptions from L<Cpanel::Transaction::File::Raw>.

=cut

sub set_value {
    my ($setting) = @_;

    unless ( defined get_action($setting) ) {
        $setting = get_setting($setting);
    }

    return 0 unless defined $setting;
    $setting = recommended_setting() if ( $setting eq DEFAULT() );

    require Cpanel::Transaction::File::Raw;

    my $trans          = Cpanel::Transaction::File::Raw->new( path => suspended_list_path(), permissions => 0640, ownership => [ 0, scalar getgrnam("mail") ] );
    my @suspended_list = grep { length $_ && $_ !~ /\A\s*\*\s*:/ } split( /\n/, $trans->get_data()->$* );

    unless ( scalar @suspended_list ) {
        push @suspended_list, _suspended_list_header();
    }

    push @suspended_list, '';
    push @suspended_list, '*: ' . get_router($setting);
    push @suspended_list, '';

    $trans->set_data( \join( "\n", @suspended_list ) );
    $trans->save_or_die();
    $trans->close_or_die();
    return 1;
}

sub _suspended_list_header {
    return << 'EO_HEADER';
# This alias list controls deliveries for all addresses belonging to suspended accounts.
# Use the WHM Exim Configuration Manager interface to alter the default (*) behavior.
#
# Wildcards are supported.
# Custom entries must be added before the default (*) entry.
#
# :unknown: or an empty aliases will use normal delivery logic.
# :blackhole: accepts the message at SMTP time and discards it.
# :fail: rejects at SMTP time with a permanent error so the sending server does not queue the message.
# :defer: rejects at SMTP time with a non-permanent error causing the sending server to queue the message.
# :queue: accepts the message at SMTP time, then queues it locally.
#
EO_HEADER
}

1;
