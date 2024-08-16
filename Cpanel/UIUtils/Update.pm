package Cpanel::UIUtils::Update;

# cpanel - Cpanel/UIUtils/Update.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::UIUtils::Update - Utility function for updating UI configs

=head1 SYNOPSIS

    use Cpanel::UIUtils::Update();

    Cpanel::UIUtils::Update::trigger_ui_updates();

=head1 DESCRIPTION

This module contains a utility function for triggering updates of the cPanel
and WHM UI caches that control what items are visible in the interfaces.

=head1 FUNCTIONS

=cut

=head2 trigger_ui_updates()

Causes cPanel and WHM to rebuild their respective caches that are used to
determine what items are displayed in the UIs.

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

None

=back

=back

=cut

sub trigger_ui_updates {

    require Cpanel::ConfigFiles;

    # Trigger dynamicui updates so FTP items for cPanel users are corrected
    require Cpanel::FileUtils::TouchFile;
    Cpanel::FileUtils::TouchFile::touchfile($Cpanel::ConfigFiles::cpanel_config_file);

    # Trigger command template updates so FTP items for WHM users are corrected
    require Whostmgr::Templates::Command::Directory;
    Whostmgr::Templates::Command::Directory::clear_cache_dir();

    return;
}

1;
