package Cpanel::ZoneFile::MigrateMX;

# cpanel - Cpanel/ZoneFile/MigrateMX.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::MigrateMX

=cut

#----------------------------------------------------------------------

use Cpanel::Time::ISO ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $change_count = migrate( $ZONE_OBJ, $OLDNAME, $NEWNAME )

Alters $ZONE_OBJ (an instance of L<Cpanel::ZoneFile>) so that all MX
records whose exchange is $OLDNAME
will use $NEWNAME as exchange instead; likewise, if the exchange is
C<mail.$OLDNAME>, it will change to C<mail.$NEWNAME>. The old records
will be commented out, with a note and a timestamp added.

The return value is the total number of modified MX records.

=cut

sub migrate {
    my ( $zone_obj, $old_mx, $new_mx ) = @_;

    my $merge_comment = sprintf 'Previous value replaced by ' . ( caller 0 )[3] . ' on ' . Cpanel::Time::ISO::unix2iso();

    my ( @comment_out, @replacements );

    for my $rec ( $zone_obj->find_records( 'type' => 'MX' ) ) {
        if ( $rec->{'exchange'} =~ m<\A(?:mail\.)?\Q$old_mx\E\z> ) {

            my %clone = %$rec;
            substr( $clone{'exchange'}, -length $old_mx ) = $new_mx;
            push @comment_out,  $rec;
            push @replacements, \%clone;
        }
    }

    if (@comment_out) {
        $zone_obj->comment_out_records( \@comment_out, $merge_comment );
    }

    for my $replc ( reverse @replacements ) {
        $zone_obj->insert_record_after_line( $replc, $replc->{'Line'} );
    }

    return 0 + @comment_out;
}

1;
