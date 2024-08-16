package Cpanel::PwCache::Map;

# cpanel - Cpanel/PwCache/Map.pm                      Copyright 2022 cPanel L.L.C
#                                                            All rights reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use strict;
use warnings;

use Colon::Config              ();
use Cpanel::PwCache::Helpers   ();
use Cpanel::LoadFile::ReadFast ();

=encoding utf-8

=head1 NAME

Cpanel::PwCache::Map - Tools for reading and serializing the system password files.

=head1 SYNOPSIS

    use Cpanel::PwCache::Map ();

    my $user_uid_map_ref = Cpanel::PwCache::Map::get_name_id_map('passwd');

    my $bob_user_uid = $user_uid_map_ref->{'bob'};

    my $group_gid_map_ref = Cpanel::PwCache::Map::get_name_id_map('group');

    my $bob_group_gid = $group_gid_map_ref->{'bob'};

=head2 $user_id_hr = get_name_id_map( DB )

… where DB is either C<passwd> or C<group>. Returns a hash reference of name => ID.

=cut

sub get_name_id_map {
    my ($db) = @_;
    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();
    if ( open( my $pwcache_passwd_fh, '<:stdio', "$SYSTEM_CONF_DIR/$db" ) ) {
        my $data = '';
        Cpanel::LoadFile::ReadFast::read_all_fast( $pwcache_passwd_fh, $data );
        return Colon::Config::read_as_hash( $data, 2 );
    }
    die "The system failed to open $SYSTEM_CONF_DIR/$db because of an error: $!";
}

1;
