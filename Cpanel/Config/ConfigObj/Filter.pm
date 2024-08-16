package Cpanel::Config::ConfigObj::Filter;

# cpanel - Cpanel/Config/ConfigObj/Filter.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
# Object to apply filter to a list of drivers
#
# Filters are named subs (anonymous or otherwise) so that you can extend the
#  list of filters when using module/class that uses the ConfigObj as it's base.

use strict;
use warnings;

use Cpanel::Config::ConfigObj::Filter::FilterList ();
use Cpanel::License::Flags                        ();
use Cpanel::Debug                                 ();

my $default_filters = {
    'enabled'                  => \&Cpanel::Config::ConfigObj::Filter::enabled_driver,
    'disabled'                 => \&Cpanel::Config::ConfigObj::Filter::disabled_driver,
    'recommended'              => \&Cpanel::Config::ConfigObj::Filter::recommended_driver,
    'spotlight'                => \&Cpanel::Config::ConfigObj::Filter::spotlight_driver,
    'licensed_by_cpanel'       => \&Cpanel::Config::ConfigObj::Filter::licensed_by_cpanel,
    'expunge_invalid_licensed' => \&Cpanel::Config::ConfigObj::Filter::remove_licensed_which_fail_license_check
};

=head1 NAME

C<Cpanel::Config::ConfigObj::Filter>

=head1 DESCRIPTION

Configuration object filter helper. We use this to retrieve various collections of C<Cpanel::Config::ConfigObj::*> providers based on various criteria.

=head1 SYNOPSIS

    use parent qw(Cpanel::Config::ConfigObj);

    sub new {
        my ($class) = shift;
        my $self = $class->SUPER::new(@_);
        return $self;
    }

    use Cpanel::Config::ConfigObj::Filter;
    my $filter = Cpanel::Config::ConfigObj::Filter->new();

    $filter->

=head1 CONSTRUCTORS

=head2 CLASS->new($USER_FILTERS, $CONFIG)

Create a new instance of the filter.

=head3 ARGUMENTS

=over

=item $USER_FILTERS - HASHREF

Additional filters to add to the system so we can perform custom filtering of the collection of installed components.

The name is the filter name and the value is a subroutine reference .

Here is a template for defining a custom filter function:

    sub($list) {
        my $data = $list->to_hash();
        foreach my $name ( keys %{$data} ) {
            if ( #condition ) {
                $list->remove($name);
            }
        }
        return 1;
    }

=item $CONFIG

The configuration object to attach the filter to.

=back

=cut

sub new {
    my ( $class, $user_defined_filters, $configObj ) = @_;

    my $internals = {
        'filters'   => {},
        'configObj' => $configObj,
    };
    my $self = bless $internals, $class;

    # use import() so default filters ref is never overridden
    $self->import($default_filters);
    $self->import($user_defined_filters);

    return $self;
}

=head1 FUNCTIONS

=head2 INSTANCE->import($FILTERS)

=head3 ARGUMENTS

=over

=item $FILTERS - HASHREF

A dictionary of filter functions.

    {
        string => sub() {

        }
    }

=back

=head3 RETURNS

The complete dictionary of filters for this instance after adding the new ones.

=cut

sub import {
    my ( $self, $filters_hr ) = @_;

    return $self->{'filters'} if ref $filters_hr ne 'HASH';

    foreach my $filter_name ( keys %{$filters_hr} ) {
        next if ref $filters_hr->{$filter_name} ne 'CODE';
        $self->{'filters'}->{$filter_name} = $filters_hr->{$filter_name};
    }

    return $self->{'filters'};
}

=head2 INSTANCE->filter($FILTER_NAME, $ARGS, $LIST)

Filter the components by the requested filter name.

=head3 ARGUMENTS

=over

=item $FILTER_NAME - string

The name of the filter to apply to the collection of components.

=item $ARGS - optional

Arguments to pass to the filter function if needed.

=item $LIST - C<Cpanel::Config::ConfigObj::Filter::FilterList>

if C<$LIST> is not passed, a C<Cpanel::Config::ConfigObj::Filter::FilterList> is created (from all available,
component drivers);

NOTE: C<$LIST> will be operated on by reference

=back

=head3 RETURNS

A C<Cpanel::Config::ConfigObj::Filter::FilterList> object.

=cut

sub filter {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $self        = shift;
    my $filter_name = shift;
    my $args        = shift;
    my $list;

    # assert that we're working on a know 'list' structure
    if ( !$_[0] || ref $_[0] ne 'Cpanel::Config::ConfigObj::Filter::FilterList' ) {
        $list = $_[0] = Cpanel::Config::ConfigObj::Filter::FilterList->new( $self->{'configObj'} );
    }
    else {
        $list = $_[0];
    }

    # only filter if we know about the filter
    if (   ( exists $self->{'filters'}->{$filter_name} )
        && ( ref $self->{'filters'}->{$filter_name} eq 'CODE' ) ) {
        my $code = $self->{'filters'}->{$filter_name};
        eval {
            $code->( $list, $args );
            1;
        } || do {
            my $msg = "Failed execute filter '$filter_name'";
            $msg = ($@) ? $msg . ': ' . $@ : $msg;
            Cpanel::Debug::log_warn($msg);
        };
    }
    return $list;
}

=head1 DEFAULT FILTER FUNCTIONS

=head2 enabled_driver($LIST)

Retain only components that are enabled.

=head3 ARGUMENTS

=over

=item $LIST - C<Cpanel::Config::ConfigObj::Filter::FilterList>

Reference to the list to remove items from.

=back

=cut

sub enabled_driver {
    my ($list) = @_;
    my $data = $list->to_hash();
    foreach my $name ( keys %{$data} ) {
        if ( !$data->{$name}->check() && !$data->{$name}->set_default() ) {
            $list->remove($name);
        }
    }
    return 1;
}

=head2 disabled_driver($LIST)

Retain only components that are disabled.

=head3 ARGUMENTS

=over

=item $LIST - C<Cpanel::Config::ConfigObj::Filter::FilterList>

Reference to the list to remove items from.

=back

=cut

sub disabled_driver {
    my ($list) = @_;
    my $data = $list->to_hash();
    foreach my $name ( keys %{$data} ) {
        if ( $data->{$name}->check() || $data->{$name}->set_default() ) {
            $list->remove($name);
        }
    }
    return 1;
}

=head2 recommended_driver($LIST)

Retain only components that are recommended by cPanel.

=head3 ARGUMENTS

=over

=item $LIST - C<Cpanel::Config::ConfigObj::Filter::FilterList>

Reference to the list to remove items from.

=back

=cut

sub recommended_driver {
    my ($list) = @_;
    my $data = $list->to_hash();
    foreach my $name ( keys %{$data} ) {
        my $metaObj = $data->{$name}->meta();
        if ( !$metaObj->is_recommended() ) {
            $list->remove($name);
        }
    }
    return 1;
}

=head2 spotlight_driver($LIST)

Retain only components that are marked to be spotlighted.

=head3 ARGUMENTS

=over

=item $LIST - C<Cpanel::Config::ConfigObj::Filter::FilterList>

Reference to the list to remove items from.

=back

=cut

sub spotlight_driver {
    my ($list) = @_;
    my $data = $list->to_hash();
    foreach my $name ( keys %{$data} ) {
        my $metaObj = $data->{$name}->meta();
        if ( !$metaObj->is_spotlight_feature() ) {
            $list->remove($name);
        }
    }
    return 1;
}

=head2 licensed_by_cpanel($LIST)

Retain only components that licensed by cPanel.

=head3 ARGUMENTS

=over

=item $LIST - C<Cpanel::Config::ConfigObj::Filter::FilterList>

Reference to the list to remove items from.

=back

=cut

sub licensed_by_cpanel {
    my ($list) = @_;
    my $data = $list->to_hash();
    foreach my $name ( keys %{$data} ) {
        if ( !$data->{$name}->isa('Cpanel::Config::ConfigObj::Interface::License') ) {
            $list->remove($name);
        }
    }
    return 1;
}

=head2 licensed_by_cpanel($LIST)

Retain only components that licensed by cPanel for use on this server.

If a component is licensed, remove if cPanel license doesn't have a valid
provision for that component; otherwise just leave in list.

=head3 ARGUMENTS

=over

=item $LIST - C<Cpanel::Config::ConfigObj::Filter::FilterList>

Reference to the list to remove items from.

=back

=cut

sub remove_licensed_which_fail_license_check {
    my ($list) = @_;
    my $data = $list->to_hash();

    my $flags = Cpanel::License::Flags::get_license_flags();

    foreach my $name ( keys %{$data} ) {
        if ( $data->{$name}->isa('Cpanel::Config::ConfigObj::Interface::License') ) {
            $list->remove($name) if ( !exists $flags->{$name} );
        }
    }
    return 1;
}

1;
