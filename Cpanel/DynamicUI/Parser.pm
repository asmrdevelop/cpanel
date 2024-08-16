package Cpanel::DynamicUI::Parser;

# cpanel - Cpanel/DynamicUI/Parser.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::JSON      ();
use Cpanel::Exception ();
use Cpanel::Autodie   ();
use Try::Tiny;

my $ALLOW_LEGACY    = 1;
my $DISALLOW_LEGACY = 0;

=head1 NAME

Cpanel::DynamicUI::Parser

=head1 DESCRIPTION

Load and parse a dyanmicui.conf file

=cut

=head1 SYNOPSIS

    use Cpanel::DynamicUI::Parser ();

    my $dui = Cpanel::DynamicUI::Parser::read_dynamicui_file('dynamicui_json.conf');
    my $dui = Cpanel::DynamicUI::Parser::read_dynamicui_file_allow_legacy('dynamicui_json.conf');
    my $dui = Cpanel::DynamicUI::Parser::read_dynamicui_file_allow_legacy('dynamicui_legacy.conf');


=cut

=head1 DESCRIPTION

=head2 read_dynamicui_file

=head3 Purpose

Read and deserialize a dynamicui.conf in the new JSON format

=head3 Arguments

=over

=item $path: string - The path to the dynamicui.conf file in the new JSON format

=back

=head3 Returns

=over

=item A deserialized version of the file

=back

If an error occurs, the function will throw an exception.

=cut

sub read_dynamicui_file ($path) {
    return _read_dynamicui_file( $path, $DISALLOW_LEGACY );
}

=head2 read_dynamicui_file_allow_legacy

=head3 Purpose

Read and deserialize a dynamicui.conf in the new JSON format or the old
LEGACY format

=head3 Arguments

=over

=item $path: string - The path to the dynamicui.conf file in the new JSON or LEGACY format

=back

=head3 Returns

=over

=item A deserialized version of the file

=back

If an error occurs, the function will throw an exception.

=cut

sub read_dynamicui_file_allow_legacy ($path) {
    return _read_dynamicui_file( $path, $ALLOW_LEGACY );
}

sub _read_dynamicui_file ( $path, $allow_legacy ) {

    Cpanel::Autodie::open( my $dui_fh, '<', $path );

    if ( Cpanel::JSON::looks_like_json($dui_fh) ) {
        return _deserialize_json_dynamicui_from_fh( $dui_fh, $path );
    }

    if ( !$allow_legacy ) {
        die Cpanel::Exception->create_raw("The system cannot load the file “$path” because its contents do not appear to be JSON.");
    }

    return _deserialize_legacy_dynamicui_from_fh($dui_fh);
}

sub _deserialize_json_dynamicui_from_fh ( $dui_fh, $path ) {

    return Cpanel::JSON::LoadFileRelaxed( $dui_fh, $path, $Cpanel::JSON::DECODE_UTF8 );
}

sub _deserialize_legacy_dynamicui_from_fh ($dui_fh) {

    local $/;
    return [
        map {
            {    # if a line has data other than whitespace or comment
                map {    ## no critic qw(ProhibitVoidMap)  # legacy
                    my ( $k, $v ) = split( m{=>}, $_, 2 );    # split the entry on =>
                    $k =~ tr{\r\t}{}d if defined $k;          # CPANEL-3551: see ticket 7423479
                    if ( defined $v ) {
                        $v =~ s/&#44;/,/g;                    # allow an encoded form of a comma
                        $v =~ tr{\r\t}{}d;                    # CPANEL-3551: see ticket 7423479
                    }
                    ( ( $k || 0 ) => ( $v || 0 ) );           # return the key => value pair
                } split( m{,}, $_ )    # Each value is separate by a , therefor iterate on those
            }
          }
          grep { !( m{\A\s*\z} || m{\A\s*#} ) }    # if a line has data other than whitespace or comment
          split( "\n", readline $dui_fh )          # split on each newline, read the line from dynamicui file
    ];
}

1;
