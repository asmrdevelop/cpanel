package Cpanel::Config::HasCpUserFile;

# cpanel - Cpanel/Config/HasCpUserFile.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles ();

=encoding utf-8

=head1 NAME

Cpanel::Config::HasCpUserFile - Functions intended to determine if a user has a cpanel users file

=head1 SYNOPSIS

    use Cpanel::Config::HasCpUserFile;

    Cpanel::Config::HasCpUserFile::has_cpuser_file('bob');

    Cpanel::Config::HasCpUserFile::has_readable_cpuser_file('bob');

=head1 DESCRIPTION

This module provides functionality to determine is a system user is a cpanel user

=cut

=head2 has_cpuser_file

Determine if a system user has a cpanel users file.

=head3 Input

$user - The system user to check

=head3 Output

C<SCALAR> true or false

=cut

# $_[0] is $user
sub has_cpuser_file {
    return 0 if !length $_[0] || $_[0] =~ tr{/\0}{};
    return -e "$Cpanel::ConfigFiles::cpanel_users/$_[0]" && -s _;
}

=head2 has_readable_cpuser_file

Determine if a system user has a cpanel users file and it
can be read by the current effective user.

=head3 Input

$user - The system user to check

=head3 Output

C<SCALAR> true or false

=cut

sub has_readable_cpuser_file {
    my ($user) = @_;
    return unless defined $user and $user ne '' and $user !~ tr/\/\0//;

    return -e "$Cpanel::ConfigFiles::cpanel_users/$user" && -s _ && -r _;
}

1;
