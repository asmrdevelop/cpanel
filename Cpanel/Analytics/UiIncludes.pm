
# cpanel - Cpanel/Analytics/UiIncludes.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Analytics::UiIncludes;

use strict;
use warnings;

use Cpanel::Analytics::Config ();

=head1 NAME

C<Cpanel::Analytics::UiIncludes>

=head1 DESCRIPTION

Methods to manage the configuration of browser-based analytics provided by UI includes.

NOTE: Analytics UI includes are disabled by default and are strictly opt-in only.

=head1 SYNOPSIS

    use Cpanel::Analytics::UiIncludes ();

    if ( Cpanel::Analytics::UiIncludes::are_enabled() ) {
        # Render one of the includes provided by the cpanel-analytics RPM
    }

=head1 FUNCTIONS

=head2 are_enabled()

Checks if the analytics UI includes are enabled and should be included.

=head3 RETURNS

Boolean - If true, analytics UI includes are enabled and should be included. If false they are disabled and should not be included.

=cut

sub are_enabled {
    return -e Cpanel::Analytics::Config::UI_INCLUDES_TOUCH_FILE() ? 1 : 0;
}

=head2 enable()

Enables the analytics UI includes.

=head3 RETURNS

Boolean - 1 if successful.

=cut

sub enable {
    require Cpanel::FileUtils::TouchFile;
    require Cpanel::SafeDir::MK;

    # TODO: Deduplicate with Cpanel::Analytics::prerequisites().
    Cpanel::SafeDir::MK::safemkdir( Cpanel::Analytics::Config::FEATURE_TOGGLES_DIR(), 0755 );

    my $result = Cpanel::FileUtils::TouchFile::touchfile(Cpanel::Analytics::Config::UI_INCLUDES_TOUCH_FILE);
    if ($result) {
        _logger()->info("cPanel interface analytics is successfully enabled");
    }
    else {
        _logger()->warn("Failed to enable cPanel interface analytics");
    }

    return $result;
}

=head2 disable()

Disables the analytics UI includes.

=head3 RETURNS

Boolean - 1 if successful.

=cut

sub disable {
    require Cpanel::Autodie;

    my $touchfile = Cpanel::Analytics::Config::UI_INCLUDES_TOUCH_FILE;

    # Cpanel::Autodie::unlink_if_exists will always attempt to unlink the file
    # and returns 1 if it was able to or 0 if it was not able to delete the file
    # because the file didn't exist. For other deletion errors it raises an
    # exception but returns undef. Since we only care if it was unable to delete
    # an existing touchfile we will view an exception as failure to disable
    # and everything else as success.
    eval { Cpanel::Autodie::unlink_if_exists($touchfile); };

    if ($@) {
        _logger()->warn("Failed to disable cPanel interface analytics");
        return 0;
    }
    else {
        _logger()->info("cPanel interface analytics is successfully disabled");
        return 1;
    }
}

my $logger;

sub _logger {
    require Cpanel::Logger;
    return $logger ||= Cpanel::Logger->new();
}

1
