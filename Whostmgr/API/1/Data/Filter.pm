package Whostmgr::API::1::Data::Filter;

# cpanel - Whostmgr/API/1/Data/Filter.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::API::1::Data::Utils ();

sub _get_filter {    ## no critic qw(Subroutines::ProhibitExcessComplexity) - its own project
    my ( $fieldspec, $args ) = @_;
    my $drill_into = \&Whostmgr::API::1::Data::Utils::evaluate_fieldspec;

    my @func_args;
    foreach my $arg ( keys %$args ) {
        if ( $arg =~ m/^arg0*(\d+)$/ ) {    #remove leading 0
            $func_args[$1] = $args->{$arg};    #sort args numerically
        }
    }
    @func_args = grep defined, @func_args;

    my $type = $args->{'type'};

    #For filters that use only one argument;
    my $term = $func_args[0];
    return if $type ne 'eq' && !length $term;    #q{} only makes sense for "eq"

    my $filter_func_hr;
    if ( $fieldspec eq '*' ) {
        $filter_func_hr = {
            'begins' => sub {
                for ( values %{ $_[0] } ) {
                    if (ref) {
                        if ( ref eq 'ARRAY' ) {
                            foreach (@$_) {
                                return 1 if m{\A\Q$term\E}i;
                            }
                        }
                    }
                    else {
                        return 1 if m{\A\Q$term\E}i;
                    }
                }

                return;
            },
            'contains' => sub {
                for ( values %{ $_[0] } ) {
                    if (ref) {
                        if ( ref eq 'ARRAY' ) {
                            foreach (@$_) {
                                return 1 if m{\Q$term\E}i;
                            }
                        }
                    }
                    else {
                        return 1 if m{\Q$term\E}i;
                    }
                }

                return;
            },
            'eq' => sub {
                for ( values %{ $_[0] } ) {
                    if (ref) {
                        if ( ref eq 'ARRAY' ) {
                            foreach (@$_) {
                                return 1 if $_ eq $term;
                            }
                        }
                    }
                    else {
                        return 1 if $_ eq $term;
                    }
                }

                return;
            },
        };
    }
    else {
        my $value;
        $filter_func_hr = {
            'contains' => sub {
                $value = $drill_into->( $fieldspec, $_[0] );
                if ( ref $value ) {
                    if ( 'ARRAY' eq ref $value ) {
                        for (@$value) {
                            return 1 if m{\Q$term\E}i;
                        }
                    }
                }
                else {
                    return 1 if $value =~ m{\Q$term\E}i;
                }

                return;
            },
            'begins' => sub {
                $value = $drill_into->( $fieldspec, $_[0] );
                if ( ref $value ) {
                    if ( 'ARRAY' eq ref $value ) {
                        for (@$value) {
                            return 1 if m{\A\Q$term\E}i;
                        }
                    }
                }
                else {
                    return 1 if $value =~ m{\A\Q$term\E}i;
                }

                return;
            },
            'eq' => sub {
                $value = $drill_into->( $fieldspec, $_[0] );
                if ( ref $value ) {
                    if ( 'ARRAY' eq ref $value ) {
                        for (@$value) {
                            return 1 if $_ eq $term;
                        }
                    }
                }
                else {
                    return 1 if $value eq $term;
                }

                return;
            },
            '==' => sub {
                $value = $drill_into->( $fieldspec, $_[0] );
                if ( ref $value ) {
                    if ( 'ARRAY' eq ref $value ) {
                        for (@$value) {
                            return 1 if $_ == $term;
                        }
                    }
                }
                else {
                    return 1 if $value == $term;
                }

                return;
            },
            'lt' => sub {
                $value = $drill_into->( $fieldspec, $_[0] );
                if ( ref $value ) {
                    if ( 'ARRAY' eq ref $value ) {
                        for (@$value) {
                            return 1 if $_ < $term;
                        }
                    }
                }
                else {
                    return 1 if !defined $value || $value !~ m{^[0-9]+$} || $value < $term;    # not handling unlimited value so far
                }

                return;
            },
            'lt_equal' => sub {
                $value = $drill_into->( $fieldspec, $_[0] );
                if ( ref $value ) {
                    if ( 'ARRAY' eq ref $value ) {
                        for (@$value) {
                            return 1 if $_ <= $term;
                        }
                    }
                }
                else {
                    return 1 if !defined $value || $value !~ m{^[0-9]+$} || $value <= $term;    # not handling unlimited value so far
                }

                return;
            },
            'lt_handle_unlimited' => sub {
                $value = $drill_into->( $fieldspec, $_[0] );
                if ( ref $value ) {
                    if ( 'ARRAY' eq ref $value ) {
                        for (@$value) {
                            return 1 if defined() && !m{\Aunlimited\z}i && $_ != 0 && $_ < $term;
                        }
                    }
                }
                else {
                    return 1 if defined($value) && $value !~ m{\Aunlimited\z}i && $value != 0 && $value < $term;
                }

                return;
            },
            'gt' => sub {
                $value = $drill_into->( $fieldspec, $_[0] );
                if ( ref $value ) {
                    if ( 'ARRAY' eq ref $value ) {
                        for (@$value) {
                            return 1 if $_ > $term;
                        }
                    }
                }
                else {
                    return 1 if defined $value && $value =~ m{^[0-9]+$} && $value > $term;    # not handling unlimited value so far
                }

                return;
            },
            'gt_equal' => sub {
                $value = $drill_into->( $fieldspec, $_[0] );
                if ( ref $value ) {
                    if ( 'ARRAY' eq ref $value ) {
                        for (@$value) {
                            return 1 if $_ >= $term;
                        }
                    }
                }
                else {
                    return 1 if defined $value && $value =~ m{^[0-9]+$} && $value >= $term;    # not handling unlimited value so far
                }

                return;
            },

            # This intentionally treats undef as greater than the supplied term since in some cases we use it for unlimited.
            # This isn't ideal but is how the filters have historically operated and we want to preserve that behavior.
            'gt_handle_unlimited' => sub {
                $value = $drill_into->( $fieldspec, $_[0] );
                if ( ref $value ) {
                    if ( 'ARRAY' eq ref $value ) {
                        for (@$value) {
                            return 1 if !defined() || m{\Aunlimited\z}i || $_ == 0 || $_ > $term;
                        }
                    }
                }
                else {
                    return 1 if !defined($value) || $value =~ m{\Aunlimited\z}i || $value == 0 || $value > $term;
                }

                return;
            },
        };
    }

    return {
        'field' => $fieldspec,
        'type'  => $type,
        'func'  => $filter_func_hr->{$type},
        'args'  => \@func_args,
    };
}

#Parameters: the API arguments, and the filters to mark done.
#Returns: the filters, or nothing if the filters aren't marked done.
sub mark_filters_done {
    my ( $api_args, @filters ) = @_;
    my $filter_args = $api_args->{'filter'} || $api_args;

    if ( $filter_args && @filters ) {
        $filter_args->{'__done'} ||= {};
        for my $f (@filters) {
            $filter_args->{'__done'}{ join q{ }, @$f } = undef;
        }

        return @filters;
    }

    return;
}

sub is_filter_done {
    my ( $api_args, $filter ) = @_;
    my $filter_args = $api_args->{'filter'} || $api_args;
    my $key         = join q{ }, @$filter;
    return $filter_args && $filter_args->{'__done'} && exists( $filter_args->{'__done'}{$key} ) ? 1 : 0;
}

#Parameters: the API arguments, and the # of records filtered.
#Returns: the # of records, or nothing if that count is not
#actually added to $api_args.
sub set_filtered_count {
    my ( $api_args, $count ) = @_;
    my $filter_args = $api_args->{'filter'} || $api_args;

    if ( $filter_args && $filter_args->{'verbose'} && defined $count ) {
        return ( $filter_args->{'filtered'} = $count );
    }

    return;
}

sub get_filtered_count {
    my ($api_args) = shift;
    my $filter_args = $api_args->{'filter'} || $api_args;

    return $filter_args && $filter_args->{'filtered'};
}

sub get_filter_funcs {
    my ( $args, $state ) = @_;
    my @filters;

    if ( exists $args->{'filter'} ) {
        $args = $args->{'filter'};
    }

    my $verbose = $state && $args->{'verbose'};

    if ($verbose) {
        $state->{'filter'} = {};
        if ( exists $args->{'filtered'} ) {
            $state->{'filter'}{'filtered'} = $args->{'filtered'};
        }
    }

    foreach my $id ( sort keys %$args ) {
        next if !Whostmgr::API::1::Data::Utils::id_is_valid($id);

        if ( 'HASH' eq ref $args->{$id} ) {

            my $filter_args = $args->{$id};
            my $fieldspec   = $filter_args->{'field'};

            #"*" is a special case for filters that aren't field-specific
            if ( $fieldspec ne '*' ) {
                next if !Whostmgr::API::1::Data::Utils::fieldspec_is_valid($fieldspec);
            }

            my $type = $filter_args->{'type'} ||= 'contains';

            my $parsed_filter = _get_filter( $fieldspec, $filter_args );

            if ( $parsed_filter && $parsed_filter->{'func'} ) {
                my $already_done;
                $already_done = is_filter_done( $args, [ $fieldspec, $type, @{ $parsed_filter->{'args'} } ] );

                if ( !$already_done ) {
                    push @filters, $parsed_filter->{'func'};
                }

                if ($verbose) {
                    my $args = $parsed_filter->{'args'};

                    $state->{'filter'}{$id} = {
                        'valid' => ( $already_done || $parsed_filter->{'func'} ) ? 1 : 0,
                        'field' => $fieldspec,
                        'type'  => $type,
                        ( map { ( 'arg' . $_ ) => $args->[$_] } ( 0 .. $#$args ) ),
                    };
                }
            }
        }
    }

    return @filters;
}

#Expects the filter structure that the API generates
sub get_filters {
    my $args = $_[0]->{'filter'} || $_[0];

    my $state = {};
    get_filter_funcs( { %$args, verbose => 1 }, $state );

    my $filter_hr = $state->{'filter'};
    my @filters;
    if ( $filter_hr && $args->{'enable'} ) {
        for my $id ( sort keys %$filter_hr ) {
            my $cur_f = $filter_hr->{$id};
            my @args;
            for my $key ( keys %$cur_f ) {
                if ( $key =~ m{arg(\d+)} ) {
                    $args[$1] = $cur_f->{$key};
                }
            }
            push @filters, [ @{$cur_f}{ 'field', 'type' }, @args ];
        }
    }

    return wantarray ? @filters : \@filters;
}

sub apply {
    my ( $args, $records, $state ) = @_;

    #Back out if the called function has already filtered the data.
    return 1 if delete $state->{'__filtered'};

    if ( exists $args->{'filter'} ) {
        $args = $args->{'filter'};
    }

    return 1 if !exists $args->{'enable'} || !$args->{'enable'};

    my @filters = get_filter_funcs( $args, $state );

    if ( $args->{'verbose'} ) {
        my $filtered = get_filtered_count($args);
        $state->{'filter'}{'filtered'} = defined $filtered ? $filtered : scalar @$records;
    }

    return 1 if !@filters;

    my @filtered_records;

  RESULT:
    foreach my $record (@$records) {
        foreach my $filter (@filters) {
            next RESULT if !$filter->($record);
        }

        push @filtered_records, $record;
    }

    @$records = @filtered_records;

    return 1;
}

1;
