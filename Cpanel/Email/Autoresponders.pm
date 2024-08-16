package Cpanel::Email::Autoresponders;

# cpanel - Cpanel/Email/Autoresponders.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Email::Autoresponders

=head1 SYNOPSIS

    my $count = Cpanel::Email::Autoresponders::count();

=head1 DESCRIPTION

This module is the beginning of what hopefully will be an abstraction
over how users’ email autoresponders are stored.

=head1 TODO

Migrate more functionality from Cpanel::API::Email into this module.

=cut

#----------------------------------------------------------------------

use Cpanel            ();
use Cpanel::Autodie   ();
use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $count = count()

Returns the total number of the current user’s autoresponders.
This throws an appropriate L<Cpanel::Exception> error on I/O failure.

=cut

sub count {
    my @responders;

    my $dir = get_dir();

    if ( Cpanel::Autodie::opendir_if_exists( my $autores_dh, $dir ) ) {
        local $!;
        @responders = grep { ( substr( $_, -5 ) eq '.json' ) || ( substr( $_, -5 ) eq '.conf' ) } readdir $autores_dh;

        die Cpanel::Exception::create( 'IO::DirectoryReadError', [ path => $dir, error => $! ] ) if $!;
    }

    return 0 + @responders;
}

=head2 $count = get_dir()

Returns the directory where the user’s autoresponders are stored.

It’s recommended to minimize use of this function since it leaks
the abstraction of how autoresponders are stored on disk.

=cut

sub get_dir {
    die 'No $Cpanel::homedir!' if !$Cpanel::homedir;

    return "$Cpanel::homedir/.autorespond";
}

1;
