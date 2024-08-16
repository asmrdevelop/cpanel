package Cpanel::Email::Lists;

# cpanel - Cpanel/Email/Lists.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Email::Lists

=head1 SYNOPSIS

    my @names = Cpanel::Email::Lists::get_names();

    my $count = Cpanel::Email::Lists::get_names();

    my $bytes = Cpanel::Email::Lists::get_total_disk_usage();

=head1 DESCRIPTION

This module contains logic for users to interface with their
mailing list storage.

=head1 TODO

Migrate more functionality from Cpanel::API::Email into this module.

=cut

#----------------------------------------------------------------------

use Cpanel                   ();
use Cpanel::Autodie          ();
use Cpanel::LoadFile         ();
use Cpanel::Mailman::Filesys ();

*_MAILING_LISTS_DIR = *Cpanel::Mailman::Filesys::MAILING_LISTS_DIR;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @names = get_names()

Returns a list of the user’s mailing lists in list context.
In scalar context, returns the number of items that would be returned
in list context.

=cut

sub get_names {
    die 'No @Cpanel::DOMAINS!' if !@Cpanel::DOMAINS;

    my $dir = _MAILING_LISTS_DIR();

    my %domain_map = map { $_ => 1 } @Cpanel::DOMAINS;

    if ( Cpanel::Autodie::opendir_if_exists( my $mhl_dirfh, $dir ) ) {
        my ( $position, $domain );

        local $!;

        return map { ( ( $position = rindex( $_, '_' ) ) > -1 && $domain_map{ ( $domain = substr( $_, $position + 1 ) ) } ) ? ( substr( $_, 0, $position ) . '@' . $domain ) : () } readdir $mhl_dirfh;
    }

    return;
}

=head2 $bytes = get_total_disk_usage()

Returns the cached amount of disk usage, in bytes, that the user’s mailing
lists occupy.

=cut

sub get_total_disk_usage {
    die 'No $Cpanel::user!' if !$Cpanel::user;

    require Cpanel::UserDatastore;
    my $dir = Cpanel::UserDatastore::get_path($Cpanel::user);

    return int( Cpanel::LoadFile::load_if_exists("$dir/mailman-disk-usage") // 0 );
}

1;
