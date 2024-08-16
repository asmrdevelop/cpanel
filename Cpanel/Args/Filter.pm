package Cpanel::Args::Filter;

# cpanel - Cpanel/Args/Filter.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::Args::Meta
);

use Cpanel::Args::Filter::Utils ();
use Cpanel::Exception           ();

my @FILTER_ARRAY_ORDER = qw(
  column
  type
  term
);

#----------------------------------------------------------------------
# NOTE: This module is "pickier" about its arguments than UAPI
# itself is. See the notes in Cpanel/Args.pm.
#----------------------------------------------------------------------

#Accepts either:
#   1) a hashref of (all required):
#       column
#       type
#       term
#   2) an arrayref with those parameters in that order.
#
sub new {
    my ( $class, $args_ref ) = @_;

    if ( ref $args_ref eq 'ARRAY' ) {
        my %args_hash;
        @args_hash{@FILTER_ARRAY_ORDER} = @$args_ref;
        $args_ref = \%args_hash;
    }

    my $type = $args_ref->{'type'};

    #We still die() here because this filter object is not valid.
    if ( !Cpanel::Args::Filter::Utils::is_valid_filter_type($type) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid filter type.', [$type] );
    }

    if ( !length $args_ref->{'term'} ) {
        if ( !grep { $_ eq $type } ( 'eq', @Cpanel::Args::Filter::Utils::EMPTY_TERM_IS_NO_OP ) ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'A filter of type “[_1]” may not have an empty [asis,term].', [$type] );
        }
    }

    return __PACKAGE__->can('SUPER::new')->( $class, $args_ref );
}

sub _required_args {
    return @FILTER_ARRAY_ORDER;
}

sub column {
    return $_[0]->{'_column'};
}

sub type {
    return $_[0]->{'_type'};
}

sub term {
    return $_[0]->{'_term'};
}

sub apply {
    my ( $self, $records_ar ) = @_;

    return Cpanel::Args::Filter::Utils::filter_by_column_type_term(
        $records_ar,
        @{$self}{qw( _column  _type  _term )},
    );
}

1;
