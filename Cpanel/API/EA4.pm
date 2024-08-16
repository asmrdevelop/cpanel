package Cpanel::API::EA4;

# cpanel - Cpanel/API/EA4.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::JSON          ();
use Cpanel::SafeDir::Read ();

our $VERSION = '1.0';

my $allow_demo = { allow_demo => 1 };

our %API = (
    get_recommendations     => $allow_demo,
    get_php_recommendations => $allow_demo,
);

=head1 SUBROUTINES

=over 4

=item get_recommendations

input: none

return: an array of available recommendations. Each recommendation is a hash reference
that should contain at least the following keys

=over 4

=item name: string

=item on: string, either add or remove

=item url: string

=item options: an array of options

=back

Each recommendation may also contain a description and level.

=cut

sub get_recommendations {
    my ( $args, $result ) = @_;

    my $recommendations = {};

    my $dir = _get_recommendations_dir();
    for my $pkg ( sort( Cpanel::SafeDir::Read::read_dir($dir) ) ) {
        if ( -d "$dir/$pkg" ) {
            for my $rec ( sort( Cpanel::SafeDir::Read::read_dir("$dir/$pkg") ) ) {
                if ( $rec =~ m/\.json$/ ) {
                    my $hr = Cpanel::JSON::LoadFile("$dir/$pkg/$rec");
                    if ( !defined $hr->{name} || !length( $hr->{name} ) ) {

                        # bad 'name'
                        next;
                    }

                    if ( !defined $hr->{on} || ( $hr->{on} ne 'add' && $hr->{on} ne 'remove' ) ) {

                        # bad 'on'
                        next;
                    }

                    if ( !defined $hr->{url} || !length( $hr->{url} ) ) {

                        # bad 'url'
                        next;
                    }

                    if ( !exists $hr->{options} || ref( $hr->{options} ) ne 'ARRAY' || !@{ $hr->{options} } ) {

                        # bad 'options'
                        next;
                    }

                    my $bad_option = 0;
                    for my $opt ( @{ $hr->{options} } ) {
                        if ( !$opt->{text} ) {
                            $bad_option = 1;
                            last;
                        }

                        #TODO/YAGNI? validate $opt->{level} or $opt->{items}

                    }
                    next if $bad_option;

                    push @{ $recommendations->{$pkg} }, $hr;
                }

                # else { non-json, that is weird }
            }
        }

        # else { non-dir, that is weird }
    }

    $result->data($recommendations);

    return 1;
}

=item get_php_recommendations

input: none

return: an array of recommended php versions in the form: php54, php80, php74

=cut

sub get_php_recommendations {
    my ( $args, $result ) = @_;

    if ( !-f _get_versions_file() ) {
        $result->error("PHP recommendations file does not exist.");
        return;
    }

    my $json = eval { Cpanel::JSON::LoadFile( _get_versions_file() ) };
    if ($@) {
        require Cpanel::Debug;
        Cpanel::Debug::log_info( "Failed to load file '" . _get_versions_file() . "' as JSON: $@" );
        $result->error("Failed to load PHP recommendation file as JSON.");
        return;
    }

    $result->data( $json->{versions} );
    return 1;
}

sub _get_recommendations_dir { return '/etc/cpanel/ea4/recommendations'; }
sub _get_versions_file       { return _get_recommendations_dir() . "/custom_php_recommendation.json"; }

=back

=cut

1;
