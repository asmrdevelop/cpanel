
# cpanel - Whostmgr/ModSecurity/Chunk/Get.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::Chunk::Get;

use strict;

use Cpanel::Locale 'lh';
use Whostmgr::ModSecurity        ();
use Whostmgr::ModSecurity::Parse ();

=head1 NAME

Whostmgr::ModSecurity::Chunk::Get

=head2 get_chunk()

Helper function that, given a config and id, returns the chunk object for the rule in question.

=cut

sub get_chunk {
    my ( $config, $id ) = @_;
    my $result = Whostmgr::ModSecurity::Parse::get_chunk_objs( Whostmgr::ModSecurity::get_safe_config_filename($config) );
    my ($chunk) = grep { $_->id && $_->id eq $id } @{ $result->{chunks} };
    if ( !$chunk ) {
        die lh()->maketext('That rule does not exist.') . "\n";
    }
    return $chunk;
}

1;
