package Whostmgr::Hostname::History;

# cpanel - Whostmgr/Hostname/History.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Hostname::History

=head1 SYNOPSIS

    use Whostmgr::Hostname::History ();

    my $file = Whostmgr::Hostname::History::file();

=head1 DESCRIPTION

This module provides common logic for the hostname history
datastore.

=cut

# Exposed for testing
our $_DIR  = '/var/cpanel';
our $_FILE = 'hostname_history.json';

=head2 $file = file()

Returns the path of the datastore’s file.

=cut

sub file {
    return "$_DIR/$_FILE";
}

=head2 clear()

Removes the datastore's file.

=cut

sub clear {
    require Cpanel::Autodie;
    return Cpanel::Autodie::unlink_if_exists( file() );
}

1;
