package Cpanel::Result;

# cpanel - Cpanel/Result.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Exception           ();
use Cpanel::APICommon::Error    ();
use Cpanel::Args::Filter::Utils ();

my $locale;

sub new {    ##no critic qw(RequireArgUnpacking)
    return bless {
        data               => undef,
        errors             => undef,    ## becomes an array_ref
        warnings           => undef,    ## becomes an array_ref
        messages           => undef,    ## becomes an array_ref
        status             => 1,        ## assume success!
        '_done_filters'    => [],
        '_done_sorts'      => [],
        '_done_pagination' => undef,
        '_total_results'   => undef,
        'metadata'         => {},

        #_stage => undef,  ## volatile temporary value, only used if $customEvents
      },
      $_[0];
}

# Used to “promote” a result from an API invocation method that
# doesn’t return an object.
sub new_from_hashref {

    # The weird reference-to-dereferenced-hashref is a failsafe
    # against inputs that aren’t hash references.
    return bless \%{ $_[1] }, $_[0];
}

# Useful for “proxying” one API result to another.
sub copy_from {
    my ( $self, $source_obj ) = @_;

    %$self = %$source_obj;

    return $self;
}

sub _reset_transform_state {    ##no critic qw(RequireArgUnpacking)
    $_[0]->{'_done_filters'}  = [];
    $_[0]->{'_done_sorts'}    = [];
    $_[0]->{'_total_results'} = $_[0]->{'_done_pagination'} = undef;
    delete $_[0]->{metadata}{'records_before_filter'};
    return;
}

## gets or sets 'data'
sub data {
    return $_[0]->{'data'} if @_ == 1;
    $_[0]->_reset_transform_state();
    $_[0]->{'data'} = $_[1];

    return 0 if $_[0]->errors();
    return 1;
}

## [% FOR err = result.errors %]
## returns 'errors'
sub errors ($self) {
    return $self->{'errors'};
}

sub warnings ($self) {
    return $self->{'warnings'};
}

sub errors_as_string ( $self, $joiner = undef ) {

    $joiner //= "\n";

    my $array = $self->{'errors'} || [];
    return join( $joiner, @$array );
}

sub set_typed_error ( $self, $type, @extra ) {
    $self->data( Cpanel::APICommon::Error::convert_to_payload( $type, @extra ) );

    return $self;
}

## These limited number of special methods prevents duplication of verbose error keys in almost every API call
##     *without* requiring a legacy lang style lookup hash or legacy style arbitrary keys.
sub error_demo {
    my ( $self, $feature ) = @_;
    return $self->error( 'This feature “[_1]” is disabled in demo mode.', $feature );
}

sub error_feature {
    my ( $self, $option ) = @_;
    return $self->error( 'This feature requires the “[_1]” option and is not enabled on your account.', $option );
}

sub error_quota {
    my ($self) = @_;
    return $self->error('Quota limitation prevent this feature from functioning.');
}

sub error_weak {
    my ( $self, $min_strength ) = @_;
    return $self->error( 'The password you selected cannot be used. This system requires stronger passwords for this service. Please select a password with a higher strength rating. Required strength: [_1]', $min_strength );
}

## $result->error('xxx [_1] zzz', 'yyy');
## appends to 'errors'
sub error {
    my ( $self, $msg, @opt_locale ) = @_;
    return unless ( defined $msg && $msg !~ m/^\s*$/ );
    _messaging( $self, 'errors', $msg, \@opt_locale );
    return;
}

sub raw_error ( $self, $text ) {

    push( @{ $self->{'errors'} }, $text ) if ( defined $text );
    return;
}

sub raw_warning ( $self, $text ) {

    push( @{ $self->{'warnings'} }, $text ) if ( defined $text );
    return;
}

## [% FOR msg = result.messages %]
## returns 'messages'
sub messages ($self) {
    return $self->{'messages'};
}

sub messages_as_string ( $self, $joiner = undef ) {

    $joiner //= "\n";

    my $array = $self->{'messages'} || [];
    return join( $joiner, @$array );
}

## $result->message('xxx [_1] zzz', 'yyy');
## appends to 'messages'
sub message {
    my ( $self, $msg, @opt_locale ) = @_;
    return unless ( defined $msg && !$msg =~ m/^\s*$/ );
    _messaging( $self, 'messages', $msg, \@opt_locale );
    return;
}

sub raw_message {
    my ( $self, $text ) = @_;
    push( @{ $self->{'messages'} }, $text ) if ( defined $text );
    return;
}

sub _messaging {
    my ( $self, $slot, $msg, $opt_locale ) = @_;

    my $text;

    #We sometimes get things from APIs that have brackets,
    #which Locale will try to parse as bracket notation … which
    #leads to exceptions.
    #
    #The real problem seems to be that the makevar() here is running
    #on things that it should not be.
    #
    #Anyhow, this falls back to just blitting the un-makevar()’d
    #message if the makevar() fails.
    #
    require Cpanel::Locale;
    try {
        $locale ||= Cpanel::Locale->get_handle();
        $text = $locale->makevar( $msg, @$opt_locale );    # $result->error() && $result->message() are consumed via a TPDS
    }
    catch {
        $text = $msg;
    };

    my $prepend = '';
    if ( exists $self->{'_stage'} && defined $self->{'_stage'} ) {
        $prepend = '[' . $self->{'_stage'} . ' stage] ';
    }
    push( @{ $self->{$slot} }, $prepend . $text );
    return;
}

## gets or sets the internal 'total_results' variable
sub total_results {
    my ( $self, $total_results ) = @_;
    if ( scalar @_ > 1 ) {
        $self->{'_total_results'} = $total_results;
        return;
    }

    return $self->{'_total_results'};
}

## gets or sets 'status'
# $_[0] = $self
# $_[1] = $status
sub status {
    if ( scalar @_ > 1 ) {
        ## ensure 'status' is actually a 1 or 0
        $_[0]->{'status'} = $_[1] ? 1 : 0;
        return;
    }
    return $_[0]->{'status'};
}

## gets or sets 'metadata'
sub metadata {
    my ( $self, $key, $val ) = @_;
    if ( scalar @_ > 2 ) {
        $self->{metadata}->{$key} = $val;
        return;
    }
    if ( defined $self->{metadata} ) {
        if ( !$key ) {
            return $self->{metadata};
        }
        else {
            if ( ref( $self->{metadata} ) eq 'HASH' ) {
                return $self->{metadata}->{$key};
            }
        }
    }

    return;
}

sub stage {
    my ( $self, $val ) = @_;
    if ( scalar @_ > 1 ) {
        if ( defined $val ) {
            $self->{'_stage'} = $val;
        }
        else {
            ## '_stage' is a very volatile context variable, currently only
            ##   used in the case of $customEvents; may as well delete
            ##   it when no longer needed; see &Cpanel::API::execute
            delete $self->{'_stage'};
        }
    }
    return $self->{'_stage'};
}

sub _apply_columns_select {
    my ( $self, $args ) = @_;

    my $columns_hash = $args->columns();
    return if !$columns_hash;

    die if !$columns_hash->isa('Cpanel::Args::Columns');

    my $records = $self->data();

    my $column_message;
    my @invalid_columns = qw();
    $columns_hash->apply( $columns_hash->{'_columns'}, $records, \$column_message, \@invalid_columns );

    #If we get a localized message we pass it to the API response
    $self->raw_message($column_message)                        if $column_message;
    $self->{'metadata'}{'invalid_columns'} = \@invalid_columns if @invalid_columns;

    return;
}

#Accepts a Cpanel::Args instance
sub _apply_non_wildcard_filters {
    my ( $self, $args ) = @_;

    my $filters_ar = $args->filters();

    return if !@$filters_ar;

    my $records = $self->data();

    if ( !defined $self->metadata('records_before_filter') ) {
        $self->metadata( 'records_before_filter', scalar @$records );
    }

    return unless @$records;

    for my $filter (@$filters_ar) {
        next if grep { $_ eq $filter } @{ $self->{'_done_filters'} };

        #This will skip over any wildcard filters.
        next if !exists $records->[0]->{ $filter->column() };

        $filter->apply($records);

        $self->mark_as_done($filter);
    }

    return;
}

#Accepts a Cpanel::Args instance
sub _apply_sorts {

    # $_[0] = self
    # $_[1] = args
    my $records;
    my $sorts_ar = $_[1]->sorts();

    #The reverse() here is important; in tandem with Perl's stable sort,
    #it allows us to implement SQL "ORDER BY" simply and efficiently.
    for my $sort ( reverse @$sorts_ar ) {
        next if grep { $_ eq $sort } @{ $_[0]->{'_done_sorts'} };

        $records ||= $_[0]->data();

        if (@$records) {

            #Sorts must be done in order, so if we can't do
            #the 2nd sort, we also can't do the last sort, even
            #if we do have the data to do the last sort.
            last if !exists $records->[0]->{ $sort->column() };

            $sort->apply($records);
        }

        $_[0]->mark_as_done($sort);
    }

    return;
}

my %done_item_list = qw(
  Cpanel::Args::Filter    _done_filters
  Cpanel::Args::Sort      _done_sorts
  Cpanel::Args::Paginate  _done_pagination
);

#GENERALLY, there is no need to call this function publicly;
#the exception is if an API call itself handles the filtering, sorting,
#or paginating. This should probably only happen if something outside
#Perl is doing those transformations.
sub mark_as_done {
    my ( $self, $whats_done ) = @_;
    keys %done_item_list;    #reset the hash pointer

    while ( my ( $class, $done_key ) = each %done_item_list ) {
        if ( UNIVERSAL::isa( $whats_done, $class ) ) {
            if ( UNIVERSAL::isa( $self->{$done_key}, 'ARRAY' ) ) {
                push @{ $self->{$done_key} }, $whats_done;
            }
            else {
                $self->{$done_key} = $whats_done;
            }

            return;
        }
    }

    die Cpanel::Exception::create( 'InvalidParameter', 'The argument to “[_1]” must be an instance of one of these classes: [join,~, ,_2]. You passed in: [_3]', [ 'mark_as_done', [ sort keys %done_item_list ], $whats_done ] );
}

sub finished_filters {
    return [ @{ $_[0]->{'_done_filters'} } ];
}

sub finished_sorts {
    return [ @{ $_[0]->{'_done_sorts'} } ];
}

sub finished_paginate {
    return $_[0]->{'_done_pagination'};
}

# $_[0] = $self
# $_[1] = $args
sub unfinished_filters {
    my @unfinished;

    for my $filter ( @{ $_[1]->filters() } ) {
        if ( !grep { $_ eq $filter } @{ $_[0]->{'_done_filters'} } ) {
            push @unfinished, $filter;
        }
    }

    return \@unfinished;
}

# $_[0] = $self
# $_[1] = $args
sub unfinished_sorts {
    my @unfinished;

    for my $sort ( @{ $_[1]->sorts() } ) {
        if ( !grep { $_ eq $sort } @{ $_[0]->{'_done_sorts'} } ) {
            push @unfinished, $sort;
        }
    }

    return \@unfinished;
}

#----------------------------------------------------------------------
#Filter/sort/paginate functions: both take a Cpanel::Args instance.

#This function can be called multiple times but will not "finalize"
#the filter/sort/pagination until all sorts are done.
#NOTE: Use this for "in-processing" within a UAPI function.

# $_[0] = $self
# $_[1] = $args
sub apply_non_wildcard_filters_sorts_pagination {
    $_[0]->_apply_non_wildcard_filters( $_[1] );
    $_[0]->_apply_sorts_and_pagination( $_[1] );
    return;
}

# $_[0] = $self
# $_[1] = $args
#NOTE: Use this ONLY when the data are fully assembled, probably
#as a last step before returning the data to the UAPI caller.
sub apply_any_filters_sorts_pagination {
    $_[0]->_apply_columns_select( $_[1] );
    $_[0]->_apply_non_wildcard_filters( $_[1] );
    $_[0]->_apply_wildcard_filters( $_[1] );
    $_[0]->_apply_sorts_and_pagination( $_[1] );
    return;
}

#----------------------------------------------------------------------

# $_[0] = $self
# $_[1] = $args
sub _apply_sorts_and_pagination {

    #We *could* apply sorts without doing all of the filters,
    #but there's usually not much point.
    if ( !@{ $_[0]->unfinished_filters( $_[1] ) } ) {
        $_[0]->_apply_sorts( $_[1] );

        #We definitely can't paginate until all of the filters
        #and sorts are done.
        if ( !@{ $_[0]->unfinished_sorts( $_[1] ) } ) {
            $_[0]->_do_pagination_without_filter_sort( $_[1] );
        }
    }

    return;
}

sub _apply_wildcard_filters {
    my ( $self, $args ) = @_;

    for my $filter ( @{ $args->filters() } ) {
        next if !Cpanel::Args::Filter::Utils::column_is_wildcard( $filter->column() );

        $filter->apply( $self->data() );

        $self->mark_as_done($filter);
    }

    return;
}

# $_[0] = $self
# $_[1] = $args
sub _do_pagination_without_filter_sort {
    my $pagination = $_[1]->paginate();

    if ( $pagination && !$_[0]->{'_done_pagination'} ) {
        $_[0]->total_results( $pagination->apply( $_[0]->data() ) );

        $_[0]->mark_as_done($pagination);
    }

    return;
}

BEGIN {

    # for perlpkg:
    no warnings 'once';

    *force_pagination = \&_do_pagination_without_filter_sort;
}

sub for_public {
    my ($self) = @_;

    return { map { m{\A_} ? () : ( $_ => $self->{$_} ) } keys %$self };
}

# Will break cpanel.pl::docpanelaction / uapi path if not here
sub TO_JSON {
    my ($self) = @_;

    #unbless would be better
    return { %{$self} };
}

1;
