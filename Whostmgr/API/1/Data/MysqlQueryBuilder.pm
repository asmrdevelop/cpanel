
# cpanel - Whostmgr/API/1/Data/MysqlQueryBuilder.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::API::1::Data::MysqlQueryBuilder;

use strict;
use warnings;

use Carp ();
use Cpanel::Locale 'lh';
use Cpanel::MysqlUtils::Quote ();

my ( @required_args, @optional_args );

BEGIN {
    @required_args = qw(metadata api_args table columns);
    @optional_args = qw(debug sort_ip);
}

##########################################################################
## Public                                                               ##
##########################################################################

sub new {
    my ( $package, %args ) = @_;
    my $self = {};
    for my $arg_name (@required_args) {
        $self->{$arg_name} = delete $args{$arg_name} || Carp::croak( lh()->maketext( q{“[_1]” is required.}, $arg_name ) );
    }
    for my $arg_name (@optional_args) {
        if ( defined( my $value = delete $args{$arg_name} ) ) {
            $self->{$arg_name} = $value;
        }
    }

    !keys(%args) or Carp::croak( lh()->maketext( q{Unexpected arguments: [list_and_quoted,_1]}, keys %args ) );

    return bless $self, $package;
}

sub result_query {
    my ($self) = @_;
    $self->_build_queries();
    return $self->{_result_query};
}

sub count_query {
    my ($self) = @_;
    $self->_build_queries();
    return $self->{_count_query};
}

sub mark_processing_done {
    my ($self) = @_;
    my ( $metadata, $api_args ) = @$self{qw(metadata api_args)};

    $api_args->{'sort'}{'a'}{'__done'} = 1;    # Prevent sort by xml-api. See Whostmgr::API::1::Data::Sort::_get_sort_func_list()

    $metadata->{__chunked} = 1;                # Prevent pagination by xml-api

    return 1;
}

##########################################################################
## Private                                                              ##
##########################################################################

# Builds both queries and stores them in the object for retrieval
sub _build_queries {
    my ($self) = @_;

    return if $self->{_result_query} && $self->{_count_query};

    my $api_args = $self->{api_args};

    my $where   = $self->_build_where;
    my $orderby = $self->_build_orderby;
    my $limit   = $self->_build_limit;

    my $quoted_table   = Cpanel::MysqlUtils::Quote::quote_identifier( $self->{table} );
    my $select_columns = join( ', ', map { Cpanel::MysqlUtils::Quote::quote_identifier($_) } @{ $self->{columns} } );

    my $result_query = qq{SELECT $select_columns FROM $quoted_table $where $orderby $limit};
    my $count_query  = qq{SELECT COUNT(*) FROM $quoted_table $where};

    $self->{_result_query} = $result_query;
    $self->{_count_query}  = $count_query;

    return 1;
}

# If the column is one of those listed when the object was instantiated, it's considered valid
sub _valid_column {
    my ( $self, $col ) = @_;
    return !!grep { $_ eq $col } @{ $self->{columns} };
}

# Builds the pagination component of the query
sub _build_limit {
    my ($self) = @_;

    my $api_args = $self->{api_args};

    my $limit = '';
    my ( $enable, $start, $size ) = @{ $api_args->{chunk} }{qw(enable start size)};

    # Take API 1's one-based paging offset (which should default to 1 if undefined), and subtract
    # one in order to convert to a MyMysql-appropriate (zero-based) offset.
    if ( $enable && defined $size ) {
        $start = 1 if !defined $start;
        $start--;
        $limit = 'LIMIT ' . ( $start || 0 ) . ', ' . $size;
    }

    return $limit;
}

# Builds the sorting component of the query
sub _build_orderby {
    my ($self) = @_;

    my $api_args = $self->{api_args};

    my $orderby = '';
    if ( $api_args->{'sort'}{'enable'} ) {

        # Not implementing the full API 1 sorting capabilities here, just the bits that are most likely to
        # be useful initially, with room for expansion.
        my $sort = $api_args->{'sort'}{'a'};
        my ( $field_name, $method ) = @$sort{qw(field method)};
        if ( !$self->_valid_column($field_name) ) {
            die lh()->maketext( q{Invalid field name: [_1]}, $field_name );
        }

        my $quoted_field_name = Cpanel::MysqlUtils::Quote::quote_identifier($field_name);
        my $style             = $sort->{'reverse'} ? 'DESC' : 'ASC';

        my $expr_generic = qq{$quoted_field_name $style};

        if ( $self->{sort_ip} and grep { $_ eq $field_name } @{ $self->{sort_ip} } ) {
            my $expr_ip = qq{inet_aton($quoted_field_name) $style};
            return qq{ ORDER BY $expr_ip, $expr_generic };
        }

        return qq{ ORDER BY $expr_generic};
    }
    return $orderby;
}

# Builds the filtering component of the query
sub _build_where {
    my ($self) = @_;

    my $api_args = $self->{api_args};

    my $where = '';
    if ( $api_args->{'filter'}{'enable'} ) {

        # Same with filtering Only implementing what we need
        my $filter = $api_args->{'filter'}{'a'};
        my ( $field_name, $type, $argument ) = @$filter{qw(field type arg0)};

        $self->_valid_column($field_name) or $field_name eq '*' or die "Invalid filter field: $field_name\n";
        my @match_cols = $field_name eq '*' ? @{ $self->{columns} } : $field_name;

        if ( $type eq 'contains' ) {
            my $quoted_search_term = Cpanel::MysqlUtils::Quote::quote("%${argument}%");
            $where = 'WHERE ' . join( ' OR ', map { Cpanel::MysqlUtils::Quote::quote_identifier($_) . qq{ LIKE $quoted_search_term} } @match_cols );
        }

        # Even though the 'eq' and '==' operators are supposed to correspond to the behavior of the same-name
        # Perl operators (string comparison and numeric comparison), that's not really necessary for API queries
        # that get converted to MySQL queries, so we'll just assume that the MySQL '=' operator does the right
        # thing regardless of what type of comparison the caller actually requested. If this assumption later
        # turns out to be false, we can add in the distinction.
        elsif ( $type eq 'eq' or $type eq '==' ) {
            my $quoted_search_term = Cpanel::MysqlUtils::Quote::quote($argument);
            $where = 'WHERE ' . join( ' OR ', map { Cpanel::MysqlUtils::Quote::quote_identifier($_) . qq{ = $quoted_search_term} } @match_cols );
        }
        else {
            die qq{Only 'contains' and 'eq'/'==' filtering are implemented for this function.\n};
        }
    }
    return $where;
}

1;
