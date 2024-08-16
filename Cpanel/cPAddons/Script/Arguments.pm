
# cpanel - Cpanel/cPAddons/Script/Arguments.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::cPAddons::Script::Arguments;

use strict;
use warnings;

use Cpanel::Logger ();

my $logger;

=head1 NAME

Cpanel::cPAddons::Script::Arguments

=head1 DESCRIPTION

Utility module that handles argument expansion for Script calls.

=head1 METHODS

=head2 Cpanel::cPAddons::Script::Arguments::expand_parameters()

Expands the parameters in a array using the data passed in data argument.

A parameter is defined as:

 <constant?>([%<key>%]?)<constant?>

=head3 EXAMPLES
  Say we have the data hash of:

  {
    a => '1',
    b => {
        c => '2',
    }
  }

  The following expansion would result:

  'a'         => 'a'
  '[% a %]'   => '1'
  '[% b.c %]' => '2'
  '[% d %]'   => ''
  '[% d.e %]' => ''
  '[% a %]c'  => '1c'
  'a[% a %]'  => 'a1'
  'a[% a %]c' => 'a1c'

=head3 ARGUMENTS

=over 1

=item - params | array ref | strings to be expanded.

=item = data | hash ref | data used in the expansions.

=back

=head3 RETURNS

Array ref of expanded parameters.

=head3 SIDE EFFECTS

Any time a key path can not be found, a log entry is added so the developer can track down the issue.

=cut

sub expand_parameters {
    my ( $params, $data ) = @_;
    my @args;
    return \@args if !$params || ref $params ne 'ARRAY';

    foreach my $arg ( @{$params} ) {
        push @args, expand_parameter( $arg, $data );
    }
    return \@args;
}

=head2 Cpanel::cPAddons::Script::Arguments::expand_parameter()

Expands a string using the data passed in data argument.

=head3 ARGUMENTS

=over 1

=item param | string | string to expand. See above for details of string format.

=item data | hash ref | data used in the expansions.

=back

=head3 RETURNS

string - Expanded parameter.

=cut

sub expand_parameter {
    my ( $param, $data ) = @_;
    my @matches = ( $param =~ m/\[%\s*([\w._]*)\s*%\]/g );
    for my $match (@matches) {
        next if !$match;
        my @props = split /\./, $match;
        my $value = get_value( $data, @props ) || '';
        $param =~ s{\[%\s*\Q$match\E\s*%\]}{$value};
    }
    $param =~ s{\[%.*%\]}{};    # Make any other go away.
    return $param;
}

=head2 Cpanel::cPAddons::Script::Arguments::get_value()

Fetches a nested value from the data hash.

=head3 ARGUMENTS

=over 1

=item data | hash ref | data used in the expansions.

=item keys | list | list of keys representing the nested access request.

=back

=head3 RETURNS

The value stored at the nesting level or undef if it can't find the element requested.

=head3 SIDE EFFECTS

Any time a key path can not be found, a log entry is added so the developer can track down the issue.

=cut

sub get_value {
    my ( $data, @keys ) = @_;
    my $value = $data;

    foreach my $key (@keys) {
        if ( ref $value eq 'HASH' || UNIVERSAL::can( $value, 'isa' ) ) {

            # move one deeper into the tree
            $value = $value->{$key};
        }
        else {
            # we are off the end of the object/hash hierarchy
            $logger ||= Cpanel::Logger->new();
            $logger->info( "Attempted to access key, $key, in data that did not exists. Full key: " . join( '.', @keys ) );
            return;
        }
    }
    return $value;
}

1;
