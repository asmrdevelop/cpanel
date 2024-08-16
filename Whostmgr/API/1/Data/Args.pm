package Whostmgr::API::1::Data::Args;

# cpanel - Whostmgr/API/1/Data/Args.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Data::Args

=head1 SUBROUTINES

=head2 _parse_dot_arg()

=head3 Purpose

This method converts the dot separated names into a nested set of hashes and is
added to the hash passed into the arg_tree parameter. The value is stored in
the leaf of the new branch added.  If the specified branch already exists, the
value replaces the existing value.

=head3 Arguments

  - 'name' - Dot separated name.
  - 'value' - Value for the field.
  - 'arg_tree' - Hash reference to the tree being built.

=head3 Returns

None

=head3 Example

my $tree = {};
_parse_do_arg( 'api.test.auto', 1, $tree );

Running this will result in the following hash:

    {
        'test' => {
            'auto' => 1
        }
    }

=cut

sub _parse_dot_arg {
    my ( $name, $value, $arg_tree ) = @_;
    my @arg = split( /\./, $name );
    shift @arg;    # skip the 'api' part
    my $current_branch = $arg_tree;
    while ( scalar @arg > 1 ) {
        my $branch_name = shift @arg;
        if ( 'HASH' ne ref $current_branch->{$branch_name} ) {
            $current_branch->{$branch_name} = {};
        }
        $current_branch = $current_branch->{$branch_name};
    }
    return ( $current_branch->{ shift @arg } = $value );
}

=head2 extract_api_args()

=head3 Purpose

Extracts the API request meta data from the wire format into a tree that can be used
programatically. All items that start with the prefix 'api.' are extracted.

=head3 Arguments

    - 'form_ref' a reference to the raw form data in a simple hash.

=head3 Returns

    - A hash ref containing. The exact structure returned depends on the passed in data.

=cut

sub extract_api_args {
    my ($form_ref) = @_;
    my $api_args = {};

    # Note: grep is used because $form_ref is a Cpanel::IxHash
    # which is cheaper to do
    foreach my $name ( grep { index( $_, 'api.' ) == 0 } keys %$form_ref ) {
        _parse_dot_arg( $name, $form_ref->{$name}, $api_args );
        delete $form_ref->{$name};
    }
    return $api_args;
}

=head2 insert_api_args( $api_args_hr, $target_args_hr )

=head3 Purpose

The inverse of C<extract_api_args()>, this takes a hashref of “extracted”
API args ($api_args_hr) and inserts them into $target_args_hr.

=cut

sub insert_api_args ( $api_args, $target_args ) {
    _insert_recursor( $api_args, $target_args, 'api' );

    return;
}

sub _insert_recursor ( $cur_api_args_hr, $target_args, @parent_keys ) {    ## no critic qw(ManyArgs) - mis-parse
    for my $key ( keys %$cur_api_args_hr ) {
        if ( 'HASH' eq ref $cur_api_args_hr->{$key} ) {
            _insert_recursor( $cur_api_args_hr->{$key}, $target_args, @parent_keys, $key );
        }
        elsif ( length ref $cur_api_args_hr->{$key} ) {
            die "INVALID API ARG: $cur_api_args_hr->{$key}";
        }
        else {
            $target_args->{ join( '.', @parent_keys, $key ) } = $cur_api_args_hr->{$key};
        }
    }

    return;
}

#----------------------------------------------------------------------

=head2 build_api_args()

=head3 Purpose

Utility method to help callers build a default set of api arguments for their application.

=head3 Arguments

    a hash ref containing the following:

    - sort - hash - optional, if provided build the sort part
        - method - string - option sort method, '' by default.
        - reverse - boolean - options sort direction, 0 by default.
        - field - string - optional sort field, '' by default.
    - chunk - boolean - optional, if 1 build the pagination part
        - start - number - optional, start item number, 1 by default.
        - size - number - optional, chunk page size, 10 by default.
    - filter - boolean - optional, if 1 build the filter part
        - arg0 - string - optional, '' by default
        - type - string  - optional, '' by default
        - field - string - optional, '' by default

=head3 Returns

    - A hash ref containing a pre-build api arguments hash with passed in preferences initialized.

=cut

sub build_api_args {
    my ($args) = @_;

    my $api_args = {};

    if ( $args->{'sort'} ) {
        $args->{'sort'}     = [ $args->{'sort'} ] if 'HASH' eq ref $args->{'sort'};
        $api_args->{'sort'} = { 'enable' => 1 };
        for my $index ( 'a' .. 'z' ) {
            my $this_sort = shift @{ $args->{'sort'} } || last;
            $api_args->{'sort'}{$index} = {
                'method'  => $this_sort->{'method'}  || '',
                'reverse' => $this_sort->{'reverse'} || 0,
                'field'   => $this_sort->{'field'}   || '',
            };
        }
    }

    if ( $args->{'chunk'} ) {
        $api_args->{'chunk'} = {
            'enable'  => 1,
            'verbose' => 1,
            'start'   => $args->{'chunk'}->{'start'} || 1,
            'size'    => $args->{'chunk'}->{'size'}  || 10,
        };
    }

    if ( $args->{'filter'} ) {
        $args->{'filter'}     = [ $args->{'filter'} ] if 'HASH' eq ref $args->{'filter'};
        $api_args->{'filter'} = { 'enable' => 1, 'verbose' => 1 };
        for my $index ( 'a' .. 'z' ) {
            my $this_filter = shift @{ $args->{'filter'} } || last;
            $api_args->{'filter'}{$index} = {
                'arg0'  => $this_filter->{'arg0'}  || '',
                'type'  => $this_filter->{'type'}  || '',
                'field' => $this_filter->{'field'} || '',
            };
        }
    }

    for my $argname ( 'payload_name', 'persona' ) {
        if ( $args->{$argname} ) {
            $api_args->{$argname} = $args->{$argname};
        }
    }

    return $api_args;
}

1;
