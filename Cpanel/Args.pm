package Cpanel::Args;

# cpanel - Cpanel/Args.pm                          Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#NOTE: ----------------------------------------------------------------------
#UAPI's original implementation used API2's filter/sort/paginate code,
#which did two unexpected(-ish) things:
#   1) coerces invalid input rather than erroring out
#   2) uses 1-indexing for pagination
#
#Hopefully at a future point we can deprecate these behaviors in UAPI,
#but for the time being we continue mimicking API2. That coercion
#happens here, in one module, rather than being diffuse over Cpanel::Args::*.
#----------------------------------------------------------------------------

=pod

=encoding utf-8

=head1 NAME

Cpanel::Args - Retrieves CGI parameters for using UAPI interface.

=head1 SYNOPSIS

    my %h = ( key1 => 'val1', key2 => 'val2' );
    my $args = Cpanel::Args->new( \%h );

    #allows undef and q(), but must be given
    my ($key1) = $args->get_required( 'key1' );

    #must be given, and must not be undef nor q()
    my ($key2) = $args->get_length_required( 'key2' );

    my @things = $args->get_multiple('thing');
    my @cosas = $args->get_required_multiple('cosa');
    my @choses = $args->get_length_required_multiple('chose');

    my @unsorted_values = $args->get_args_like( qr/^key\d+$/ );

    my @unsorted_keys = $args->get_keys_like( qr/^key\d+$/ );

=head1 DESCRIPTION

This package will typically be used by anyone needing to interact
with cPanel (not WHM) customers using the UAPI CGI interface.

UAPI modules in the 'Cpanel/API' directory will never need to instantiate
this object because Cpanel::API passes each handler an instance of this
object.

=head1 INTERFACE

=cut

use cPstrict;

use Cpanel::Context     ();
use Cpanel::Exception   ();
use Cpanel::Form::Utils ();
use Cpanel::JSON        ();

#This can be called hundreds of times on a single page,
#so optimizations are worthwhile.
sub new {
    my ( $class, $args, $api_hr ) = @_;

    $args ||= {};

    my $self = bless {
        _args                => $args,
        _columns             => '',
        _pagination          => '',
        __invalid_pagination => '',
    }, $class;

    my %filter_args;
    my %sort_args;
    my %paginate_args;
    my %column_args;

    for ( keys %$args ) {
        if ( index( $_, 'api.' ) == 0 ) {
            if ( rindex( $_, 'api.paginate_', 0 ) == 0 ) {
                $paginate_args{ substr( $_, 13 ) } = $args->{$_};
            }
            if ( rindex( $_, 'api.filter_', 0 ) == 0 ) {
                $filter_args{ substr( $_, 11 ) } = $args->{$_};
            }
            if ( rindex( $_, 'api.sort_', 0 ) == 0 ) {
                $sort_args{ substr( $_, 9 ) } = $args->{$_};
            }
            if ( rindex( $_, 'api.columns_', 0 ) == 0 ) {
                push( @{ $column_args{"columns"} }, $args->{$_} );
            }
        }
    }

    #----------------------------------------------------------------------
    #NOTE: Much of the complexity below is to mimic API2's argument coercion.
    #Without that coercion, we wouldn't need the _coerce_* functions
    #or the evals.
    #----------------------------------------------------------------------

    my @filter_primitives;
    if (%filter_args) {
        require Cpanel::Args::Filter::Utils;
        require Cpanel::Args::Filter;
        @filter_primitives = Cpanel::Args::Filter::Utils::parse_filters( \%filter_args );
    }
    my ( @filter_objs, @invalid_filters );
    for my $filter_ar (@filter_primitives) {
        my @filter_copy = @$filter_ar;

        $self->_coerce_filter_args_a_la_api2($filter_ar);

        local $@;
        eval { push @filter_objs, Cpanel::Args::Filter->new($filter_ar) } or do {
            push @invalid_filters, [ \@filter_copy, $@ ];
        };
    }
    @{$self}{qw( _filters  _invalid_filters )} = ( \@filter_objs, \@invalid_filters );

    my @sort_primitives;
    if (%sort_args) {
        require Cpanel::Args::Sort::Utils;
        require Cpanel::Args::Sort;
        @sort_primitives = Cpanel::Args::Sort::Utils::parse_sorts( \%sort_args );
    }
    my ( @sort_objs, @invalid_sorts );
    for my $sort_ar (@sort_primitives) {
        my %sort_hash;
        @sort_hash{qw( column  reverse  method )} = @$sort_ar;

        my %sort_copy = %sort_hash;

        #NOTE: Unimplemented as of 11.42, but left in for future expansion
        # If we later want to define return data types so the api
        # can know how to sort the data without external knowledge
        # we can add this here and update the tests.
        if ( !length $sort_hash{'method'} && $api_hr ) {
            $sort_hash{'method'} = $api_hr->{'sort_method'}{ $sort_hash{'column'} };
        }

        $self->_coerce_sort_args_a_la_api2( \%sort_hash );

        local $@;
        eval { push @sort_objs, Cpanel::Args::Sort->new( \%sort_hash ) } or do {
            push @invalid_sorts, [ \%sort_copy, $@ ];
        };
    }
    @{$self}{qw( _sorts  _invalid_sorts )} = ( \@sort_objs, \@invalid_sorts );

    if (%paginate_args) {
        require Cpanel::Args::Paginate;
        my %paginate_copy = %paginate_args;

        $self->_coerce_paginate_args_a_la_api2( \%paginate_args );

        #api.paginate_start uses 1-indexing, but internally we use 0-indexing.
        if ( $paginate_args{'start'} ) {
            $paginate_args{'start'} -= 1;
        }

        local $@;
        eval { $self->{'_pagination'} = Cpanel::Args::Paginate->new( \%paginate_args ) } or do {
            $self->{'_invalid_pagination'} = [ \%paginate_copy, $@ ];
        };
    }

    if (%column_args) {
        require Cpanel::Args::Columns;
        $self->{'_columns'} = Cpanel::Args::Columns->new( \%column_args );
    }

    return $self;
}

sub _coerce_filter_args_a_la_api2 {
    my ( $self, $args_ar ) = @_;

    if ( !$args_ar->[1] ) {
        require Cpanel::Api2::Filter;
        no warnings 'once';
        $args_ar->[1] = $Cpanel::Api2::Filter::DEFAULT_TYPE;
    }
    return;
}

sub _coerce_sort_args_a_la_api2 {
    my ( $self, $args_hr ) = @_;

    require Cpanel::Args::Sort::Utils;
    if ( !Cpanel::Args::Sort::Utils::is_valid_sort_method( $args_hr->{'method'} ) ) {
        require Cpanel::Api2::Sort;
        no warnings 'once';
        $args_hr->{'method'} = $Cpanel::Api2::Sort::DEFAULT_METHOD;
    }

    $args_hr->{'reverse'} = $args_hr->{'reverse'} ? 1 : 0;

    return;
}

sub _coerce_paginate_args_a_la_api2 {
    my ( $self, $args_hr ) = @_;

    if ( !$args_hr->{'start'} || $args_hr->{'start'} =~ tr{0-9}{}c ) {
        $args_hr->{'start'} = 0;
    }

    if ( !length $args_hr->{'size'} || $args_hr->{'size'} =~ tr{0-9}{}c || $args_hr->{'size'} < 1 ) {
        require Cpanel::Api2::Paginate;
        no warnings 'once';
        $args_hr->{'size'} = $Cpanel::Api2::Paginate::DEFAULT_PAGE_SIZE;
    }

    return;
}

=pod

$args->get( KEY1, KEY2, .. )

$args->get_required( KEY1, KEY2, ..)

$args->get_length_required( KEY1, KEY2, ..)

Retrieve the values of one or more UAPI arguments.
It is assumed that each argument was only passed in once. Missing values
are returned as undef.

May be called in scalar or list context; however,
the response is undefined when passing multiple C<KEY>s in scalar context.

C<get_required()> will throw if any requested value is missing.
C<get_length_required()> will throw if any requested value is missing,
undef, or empty-string.

=head2 INPUT

One or more argument names

=head2 OUTPUT

Zero or more values matching the argument name(s).

=head2 EXAMPLES

    my ( $yolo )  = $args->get_required( 'yolo' );  #list context only!

    my ( $yolo, $bovine )  = $args->get_required( qw( yolo bovine ) );

=cut

sub get {
    my ( $self, @keylist ) = @_;

    if ( ref( $self->{_args} ) eq 'HASH' ) {
        return @{ $self->{_args} }{@keylist};
    }
    return;
}

sub get_boolean ( $self, @keylist ) {
    return map { Cpanel::JSON::to_bool($_) } $self->get(@keylist);
}

sub get_required {
    my ( $self, @keylist ) = @_;

    if ( my @missing = grep { !exists $self->{_args}{$_} } @keylist ) {
        die Cpanel::Exception::create( 'MissingParameter', 'Provide the [list_and_quoted,_1] [numerate,_2,argument,arguments].', [ \@missing, 0 + @missing ] );
    }

    return @{ $self->{_args} }{@keylist};
}

sub get_length_required {
    my ( $self, @keylist ) = @_;

    if ( my @missing = grep { !exists $self->{_args}{$_} } @keylist ) {
        die Cpanel::Exception::create( 'MissingParameter', 'Provide the [list_and_quoted,_1] [numerate,_2,argument,arguments].', [ \@missing, 0 + @missing ] );
    }

    if ( my @empty = grep { !length $self->{_args}{$_} } @keylist ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The [list_and_quoted,_1] [numerate,_2,argument,arguments] cannot be empty.', [ \@empty, 0 + @empty ] );
    }

    return @{ $self->{_args} }{@keylist};
}

=pod

$args->get_multiple( KEY )

$args->get_required_multiple( KEY )

$args->get_length_required_multiple( KEY )

$args->get_length_multiple( KEY )

B<LIST CONTEXT ONLY.> Retrieve the values of KEY that were passed in,
assuming that those those values are given to UAPI in the manner
in which Cpanel::Form stores multiple values of the same name.

C<get_required_multiple()> will throw if there are no values for the
requested KEY.

C<get_length_required_multiple()> will throw if there are no values for the
requested KEY B<or> if any of those values is undef or empty-string.

C<get_length_multiple()> will throw if any values is empty (but will
B<not> throw if there are no such values.

=head3 INPUT

One or more argument names

=head3 OUTPUT

Zero or more values matching the argument name(s).

=head3 EXAMPLE

    my @yolos  = $args->get_multiple( 'yolo' );

=cut

sub get_multiple {
    my ( $self, $key ) = @_;

    Cpanel::Context::must_be_list();

    #NOTE: duplicated w/ Cpanel/API/Batch.pm
    my @keys = $self->get_keys_like(qr<\A\Q$key\E(?:-[0-9]+)?\z>);

    return $self->get( Cpanel::Form::Utils::restore_same_name_keys_order(@keys) );
}

sub get_required_multiple {
    my ( $self, $key ) = @_;

    Cpanel::Context::must_be_list();

    my @values = $self->get_multiple($key);
    if ( !@values ) {
        die Cpanel::Exception::create( 'MissingParameter', 'Provide at least one “[_1]” argument.', [$key] );
    }

    return @values;
}

sub get_length_required_multiple {
    my ( $self, $key ) = @_;

    Cpanel::Context::must_be_list();

    my @values = $self->get_required_multiple($key);
    _fail_if_any_empty( $key, \@values );

    return @values;
}

sub _fail_if_any_empty ( $key, $values_ar ) {
    if ( grep { !length } @$values_ar ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” arguments cannot be empty.', [$key] );
    }

    return;
}

sub get_length_multiple ( $self, $key ) {
    Cpanel::Context::must_be_list();

    my @values = $self->get_multiple($key);
    _fail_if_any_empty( $key, \@values );

    return @values;
}

sub map_length_required_multiple_to_key_values {
    my ( $self, $key, $value ) = @_;

    my @keys   = $self->get_length_required_multiple($key);
    my @values = $self->get_length_required_multiple($value);

    if ( scalar @keys != scalar @values ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Provide the same number of “[_1]” and “[_2]” arguments.', [ $key, $value ] );
    }

    my %key_to_value_map;
    @key_to_value_map{@keys} = @values;
    return \%key_to_value_map;
}

=head2 $args->get_keys_like()

B<LIST CONTEXT ONLY.> Retrieve the keys that match a given
regular expression. The keys are returned in no particular order.

=cut

sub get_keys_like {
    my ( $self, $regexp ) = @_;

    Cpanel::Context::must_be_list();

    return grep { m<$regexp> } keys %{ $self->{'_args'} };
}

=head2 $args->get_args_like()

B<LIST CONTEXT ONLY.> Retrieve the values of an argument that match a
regular expression. The values are returned in no particular order.

You might prefer C<get_multiple()>, or one of its more stringent brethren,
if what you’re wanting is multiple values of the same key. Those functions
ensure a return order and don’t compel you, the caller, to make assumptions
about how C<Cpanel::Form> handles multiple occurrences of the same key.

=head3 INPUT

Regex - scalar (qr//)

=head3 OUTPUT

list - one or more values matching regex

=head3 EXCEPTIONS

N/A

=head3 EXAMPLE

   my @vals = $args->get_args_like( qr/^foo\d+$/ );

=cut

sub get_args_like {
    my ( $self, $regex ) = @_;

    Cpanel::Context::must_be_list();

    if ( ref $self->{_args} eq 'HASH' ) {
        return ( map { $self->{_args}->{$_} } grep { $_ =~ $regex } ( keys %{ $self->{_args} } ) );
    }
}

=head2 $args->is_empty

Check if the current args list is empty or not.
Dies if any arg is provided.

=cut

sub is_empty ($self) {

    return 1 unless ref $self->{_args} eq 'HASH';

    my @exclude_rules = ( qr{^\Qapi.\E}, qr{^cpanel_jsonapi} );

    my @extras;
    foreach my $k ( sort keys $self->{_args}->%* ) {
        next if grep { $k =~ $_ } @exclude_rules;
        push @extras, $k;
    }

    if ( scalar @extras ) {
        die Cpanel::Exception::create_raw( 'InvalidParameters', 'Unrecognized API parameter(s): ' . join( ' ', @extras ) );
    }

    return 1;
}

sub exists {
    my ( $self, $key ) = @_;
    return exists $self->{_args}->{$key};
}

sub keys {
    Cpanel::Context::must_be_list();
    return keys %{ $_[0]->{_args} };
}

=head2 $args->get_uploaded_files()

Parse the arguments for uploaded files and return them in a hash
with the key being the submitted 'name' for the form.

    Example:

    # submitting the data with the following args
    {
        'file-tprc-23-header-blue.png' => '/home/tuesday/tmp/Cpanel_Form_file.upload.82113415',
        'file-tprc-23-header-blue.png-key' => 'backgroundImage',
    };

    # The reply is then formatted as
    {
      'backgroundImage' => {
                             'tmp_filepath'      => '/home/tuesday/tmp/Cpanel_Form_file.upload.3a348e00',
                             'original_filename' => 'tprc-23-header-blue.png'
                           }
    };

=cut

sub get_uploaded_files ( $self, $allow_slash = undef ) {

    my %files;

    my $current_arg_name;
    my $current_file_name;

    foreach my $key ( reverse sort $self->keys() ) {

        # note: use 'reverse sort' so '-key' appears before the file path
        next unless $key =~ qr{^file-(.+)$};
        my $name = $1;
        my $v    = $self->get($key);

        if (   defined $current_file_name
            && defined $current_arg_name
            && $name eq $current_file_name ) {

            if ( -e $v && _is_safe_file_name( $name, $allow_slash ) ) {
                $files{$current_arg_name} = {
                    tmp_filepath      => $v,
                    original_filename => $name,
                };
            }

            undef $current_file_name;
            undef $current_arg_name;

            next;
        }

        if ( $name =~ s{-key$}{} ) {
            $current_file_name = $name;
            $current_arg_name  = $v;
        }
    }

    return \%files;
}

sub _is_safe_file_name ( $file, $allow_slash = undef ) {

    return 1 unless length $file;

    return if $file                  =~ m/^(\.|\.\.)$/;    # refuse . and ..
    return if $file                  =~ tr/<>;//;          # refuse script special ones
    return if !$allow_slash && $file =~ tr{/}{};           # refuse slashes

    return 1;
}

sub add {
    my ( $self, $key, $value ) = @_;
    $self->{_args}->{$key} = $value;
    return;
}

sub get_raw_args_hr {
    return $_[0]->{_args};
}

#----------------------------------------------------------------------
#NOTE: The following functions do NOT deep-clone;
#operations on individual items DO persist!

=head2 filters

Delivers an arrayref of Cpanel::Args::Filters objects corresponding to the
passed in filters. Processing the filters is still up to the caller.

=head3 SEE ALSO

Cpanel::Args::Filters::Utils - On how to process filters from this

=cut

sub filters ($self) {
    return [ $self->{'_filters'}->@* ];
}

sub sorts ($self) {
    return [ $self->{'_sorts'}->@* ];
}

sub paginate ($self) {
    return $self->{'_pagination'};
}

sub columns ($self) {
    return $self->{'_columns'};
}

=head2 has_column(NAME)

Checks if the return column is listed in the columns collection.

=head3 ARGUMENTS

=over

=item NAME - string

Name of the column to look for in the requested columns list.

=back

=head3 RETURNS

1 if the column should be included, 0 otherwise. If no columns are specified in the request assume all columns are returned.

=head3 EXAMPLES

 my $args = new Cpanel::Args({
    'api.column_1' => 'id',
    'api.column_2' => 'name'
 });

 if ( $args->has_column('id') ) {
    print "requested id";
 } else {
    print "id not requested";
 }

=cut

sub has_column {

    # SIGNATURE: (self, name)
    return 1 if !$_[0]->columns;

    return scalar( grep { $_ eq $_[1] } @{ $_[0]->columns->{'_columns'} } ) ? 1 : 0;
}

#Returns an arrayref of arrays, each of which is:
#   0) The raw arguments given
#   1) The Cpanel::Exception object that contains the error.
sub invalid_filters ($self) {
    return [ $self->{'_invalid_filters'}->@* ];
}

#Returns an arrayref of arrays, each of which is:
#   0) The raw arguments given
#   1) The Cpanel::Exception object that contains the error.
#NOTE: Because we "coerce" invalid sort parameters, as of 11.42 this
#never returns anything useful.
sub invalid_sorts ($self) {
    return [ $self->{'_invalid_sorts'}->@* ];
}

#Returns either undef or:
#   0) The raw arguments given
#   1) The Cpanel::Exception object that contains the error.
sub invalid_paginate ($self) {
    return $self->{'_invalid_pagination'};
}

1;
