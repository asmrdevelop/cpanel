package Cpanel::DB::Map::Reader::Exists;

# cpanel - Cpanel/DB/Map/Reader/Exists.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie       ();
use Cpanel::DB::Map::Path ();
use Cpanel::ConfigFiles   ();

=encoding utf-8

=head1 NAME

Cpanel::DB::Map::Reader::Exists - Check to see if a cpanel user exists in the db map.

=head1 SYNOPSIS

    use Cpanel::DB::Map::Reader::Exists;

    if (Cpanel::DB::Map::Reader::Exists::cpuser_exists('bob')) {
        die "no you may not";
    }

=head2 cpuser_exists( CPUSER )

This determines if the DB Map has an entry for a given cPanel username.

 Parameters:
   CPUSER  - The name of the cpuser for which to check for a DB Map entry.

 Returns:
   1 - a DB map entry exists for the cpuser
   0 - no DB map entry exists for the cpuser

=cut

my $_dash_e = \&Cpanel::Autodie::exists;

sub cpuser_exists {
    my ($cpuser) = @_;

    my $exists = $_dash_e->( Cpanel::DB::Map::Path::data_file_for_username($cpuser) );

    $exists ||= $_dash_e->("$Cpanel::ConfigFiles::DATABASES_INFO_DIR/$cpuser.yaml");

    return $exists || 0;
}

1;
