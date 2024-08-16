package Cpanel::DB::Map::Remove;

# cpanel - Cpanel/DB/Map/Remove.pm                          Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DB::Map::Path ();
use Cpanel::Autodie       ();

=encoding utf-8

=head1 NAME

Cpanel::DB::Map::Remove - Remove a user from the db map

=head1 SYNOPSIS

    use Cpanel::DB::Map::Remove;

    Cpanel::DB::Map::Remove::remove_cpuser('bob');

=head2 remove_cpuser($cpuser)

Removes a user from the db map.

=over 2

=item Input

=over 3

=item $cpuser C<SCALAR>

    The cPanel username to remove from the dbmap.

=back

=item Output

Returns 1 on success or dies on failure.

=back

=cut

sub remove_cpuser {
    my ($cpuser) = @_;

    my $ds_path = Cpanel::DB::Map::Path::data_file_for_username($cpuser);

    Cpanel::Autodie::unlink_if_exists($ds_path);

    require Cpanel::DB::Map::Convert;

    Cpanel::DB::Map::Convert::remove_old_dbmap($cpuser);

    return 1;
}

1;
