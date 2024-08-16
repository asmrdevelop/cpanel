package Cpanel::Fileman::Reserved;

# cpanel - Cpanel/Fileman/Reserved.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 DESCRIPTION

A light weight module to provide a list of directories reserved for cPanel use.

=cut

our @_RESERVED = qw/.cpanel .htpasswds .spamassassin .ssh .trash access-logs
  cgi-bin etc logs mail perl5 ssl tmp var/;

=head1 METHODS

=head2 is_reserved

Determines if a directory is reserved for cPanel use.

=head3 Required arguments

=over 4

=item directory

The directory path to be tested. It should be a relative path to the user home directory.

=back

=head3 Returns

Returns true for all reserved directories and sub-directories. Resturns false otherwise.

=cut

sub is_reserved {
    my ($dir) = @_;
    $dir =~ s{^/+}{};
    $dir =~ s{/+$}{};
    $dir .= '/';
    foreach my $reserved (@_RESERVED) {
        return 1 if $dir =~ m,^\Q$reserved\E/,;
    }

    return 0;
}

1;
