package Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/SuspendOrHoldOutgoingMail/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);

our $VERSION = '1.1';

=encoding utf-8

=head1 NAME

Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail::META - Feature showcase META for Suspend Outgoing Mail

=head1 SYNOPSIS

    use Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail::META;

    my $content = Cpanel::Config::ConfigObj::Driver::SuspendOrHoldOutgoingMail::META::content();


=head1 DESCRIPTION

Feature Showcase metadata for Suspend and Hold Outgoing Mail for Webmail Users

=cut

=head2 meta_version

Gets the version of the driver META object

=over 2

=item Output

=over 3

=item C<SCALAR>

    Returns the version of the META object

=back

=back

=cut

sub meta_version {
    return $VERSION;
}

=head2 get_driver_name

Gets the driver name for the feature showcase META object

=over 2

=item Output

=over 3

=item C<SCALAR>

    Returns the driver name for the feature showcase META object

=back

=back

=cut

use constant get_driver_name => 'suspend_or_hold_outgoing_mail';

=head2 content

Returns all the information unique to this feature showcase.

=over 2

=item Input

=over 3

=item C<CODEREF>

    $locale_handle - when a locale handle is passed, the strings will be translated

=back

=item Output

=over 3

=item C<HASHREF>

    Return content details object for the feature showcase item

=back

=back

=cut

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/featureshowcaseholdmail',
        'name'   => {
            'short'  => 'Suspend or Hold Outgoing Mail for Webmail Users',
            'driver' => get_driver_name(),
        },
        'since'    => '',
        'version'  => $VERSION,
        'readonly' => 1,
    };

    my ( $line1, $line2 );

    if ($locale_handle) {
        $content->{'name'}->{'short'} = $locale_handle->maketext('Suspend or Hold Outgoing Mail for [asis,Webmail] Users'),
          $line1 = $locale_handle->maketext( "You can now allow, suspend, or hold an email account’s ability to send outgoing mail. Select [output,em,_1] to queue all outgoing mail, and then select [output,em,_2] to send the queue. Select [output,em,_3] to discard all outgoing messages.", $locale_handle->maketext('Hold'), $locale_handle->maketext('Allow'), $locale_handle->maketext('Suspend') );
        $line2 = $locale_handle->maketext( "You can set email suspensions in [asis,cPanel]’s “[_1]” interface ([join, ≫ ,_2]).", $locale_handle->maketext("Email Accounts"), [ 'cPanel', $locale_handle->maketext("Home"), $locale_handle->maketext("Email"), $locale_handle->maketext("Email Accounts") ] );
    }
    else {
        $line1 = "You can now allow, suspend, or hold an email account’s ability to send outgoing mail. Select Hold, to queue all outgoing mail, and then select Allow to send the queue. Select Suspend to discard all outgoing messages.";
        $line2 = "You can set email suspensions in cPanel’s “Email Accounts” interface (cPanel ≫ Home ≫ Email ≫ Email Accounts).";
    }

    $content->{'abstract'} = "<p>$line1</p><p>$line2</p>";

    $content->{'name'}->{'long'} = $content->{'name'}->{'short'};

    return $content;
}

=head2 showcase

Used to determine how the item should appear in the showcase

=over 2

=item Output

=over 3

=item C<HASHREF>

    Returns an object representing a generic feature to showcase

=back

=back

=cut

sub showcase {
    return { 'is_recommended' => 0, 'is_spotlight_feature' => 0 };
}

1;
