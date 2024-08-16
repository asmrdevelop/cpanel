
# cpanel - Cpanel/Transport/Files/GoogleDrive/CredentialFile.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files::GoogleDrive::CredentialFile;

use strict;
use warnings;

=head1 NAME

Cpanel::Transport::Files::GoogleDrive::CredentialFile

=head1 SYNOPSIS

This module is handles issues relating to the properties
of the Google Drive transport credential file

=head1 DESCRIPTION

Functionality relating to Google Drive credential file properties.

=head1 SUBROUTINES

=head2 credential_file_from_id

Returns the full path to the credential file based on the client ID.

=cut

sub credential_file_from_id {
    my ($client_id) = @_;

    return '/var/cpanel/backups/' . $client_id . '.yml';
}

1;
