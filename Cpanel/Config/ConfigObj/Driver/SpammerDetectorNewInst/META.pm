package Cpanel::Config::ConfigObj::Driver::SpammerDetectorNewInst::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/SpammerDetectorNewInst/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);
our $VERSION = 1.1;

=head1 NAME

Cpanel::Config::ConfigObj::Driver::SpammerDetectorNewInst::META

=head1 DESCRIPTION

Feature Showcase metadata for SpammerDetectorNewInst

=cut

=head1 SYNOPSIS

Metadata for the feature showcase item.

=cut

=head2 meta_version

Returns the meta version

=cut

sub meta_version {
    return 1;
}

=head2 get_driver_name

returns the driver internal name

=cut

sub get_driver_name {
    return 'spammer_detector_newinst';
}

=head2 content

returns the metadata bundle

=cut

sub content {

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => '',
        'name'   => {
            'short'  => 'Potential Spammer Notification',
            'long'   => 'Notification of Potential Spammers',
            'driver' => get_driver_name(),
        },
        'since'    => '',
        'abstract' => 'Auto-enabling the potential spammer notification',
        'version'  => $VERSION
    };

    return $content;
}

=head2 showcase

Returns whether or not this feature is showcased.

=cut

sub showcase {
    return undef;
}

=head2 auto_enable

Returns whether or not this feature is auto-enabled.

=cut

sub auto_enable {
    return 1;
}

1;
