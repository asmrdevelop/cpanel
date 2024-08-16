package Cpanel::SSL::PendingQueue::Item;

# cpanel - Cpanel/SSL/PendingQueue/Item.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Class::Accessor::Fast);

use Cpanel::Context    ();
use Cpanel::LoadModule ();
use Cpanel::Exception  ();
use Cpanel::OrDie      ();
use Cpanel::SSL::Poll  ();
use Cpanel::SSL::Utils ();

my @required_scalars;

my @required_arrays;

my @ro_accessors;

my @rw_accessors;

BEGIN {
    @required_scalars = qw(
      provider
      product_id
      order_item_id
      order_id
      csr
    );

    @required_arrays = qw(
      vhost_names
    );

    @ro_accessors = qw(
      created_time
      first_poll_time
      last_poll_time
      validation_type
    );

    @rw_accessors = qw(
      last_action_urls
      last_status_code
      last_status_message
      status
    );

    __PACKAGE__->mk_ro_accessors(
        @required_scalars,
        @ro_accessors,
    );

    __PACKAGE__->mk_accessors(@rw_accessors);
}

our $_TEST_NOW;
sub _now { return $_TEST_NOW || time }

sub new {
    my ( $class, $args_hr ) = @_;

    local $args_hr->{'created_time'} = $args_hr->{'created_time'} || _now();
    local $args_hr->{'status'}       = $args_hr->{'status'}       || 'unconfirmed';

    local $args_hr->{'validation_type'} ||= 'dv';

    my @missing_required_parms = (
        ( grep { !exists $args_hr->{$_} } @required_scalars ),
        ( grep { !$args_hr->{$_} || !@{ $args_hr->{$_} } } @required_arrays ),
    );

    if (@missing_required_parms) {
        die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing_required_parms ] );
    }

    #This validates the “csr” value.
    $args_hr->{'csr_parse'} ||= Cpanel::OrDie::multi_return(
        sub {
            Cpanel::SSL::Utils::parse_csr_text( $args_hr->{'csr'} );
        },
    );

    #For pre-v74 datastores.
    $args_hr->{'domain_dcv_method'} ||= { map { ( $_ => 'http' ) } @{ $args_hr->{'csr_parse'}{'domains'} } };

    my $self = $class->SUPER::new($args_hr);

    return $self;
}

sub is_ready_to_poll {
    my ($self) = @_;

    return 1 if grep { !$_ } @{$self}{qw(first_poll_time last_poll_time)};

    my $func = "next_poll_time_$self->{'validation_type'}";

    my $next_poll_time = Cpanel::SSL::Poll->can($func)->( @{$self}{qw(first_poll_time last_poll_time)} );

    return ( time() > $next_poll_time ) ? 1 : 0;
}

sub update_poll_times {
    my ($self) = @_;

    my $now = time;

    $self->{'first_poll_time'} ||= $now;
    $self->{'last_poll_time'} = $now;

    return;
}

sub domains {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    my @domains = @{ $self->csr_parse()->{'domains'} };

    my %domains_lookup;
    @domains_lookup{@domains} = ();

    #strip out “www”s
    return grep { ( substr( $_, 0, 4 ) ne 'www.' ) || !exists $domains_lookup{s<\Awww.><>r} } @domains;
}

sub _deep {
    my ( $self, $attr ) = @_;

    Cpanel::LoadModule::load_perl_module('Clone');

    return Clone::clone( $self->{$attr} );
}

sub csr_parse {
    my ($self) = @_;

    return $self->_deep('csr_parse');
}

sub domain_dcv_method {
    my ($self) = @_;

    return $self->_deep('domain_dcv_method');
}

sub identity_verification {
    my ($self) = @_;

    return $self->_deep('identity_verification');
}

sub vhost_names {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    #A small chink in the abstraction …
    return @{ $self->{'vhost_names'} };
}

sub to_hashref {
    my ($self) = @_;

    my %plain_hash = (

        #Need to copy these arrays so that the caller
        #can’t change the object’s internals.
        #This will need to use clone() if we ever return
        #anything beyond a list of scalars here!
        ( map { $_ => [ $self->$_() ] } @required_arrays ),

        map { $_ => $self->$_() } (
            @required_scalars,
            @ro_accessors,
            @rw_accessors,
            'csr_parse',
            'identity_verification',
            'domain_dcv_method',
        ),
    );

    return \%plain_hash;
}

1;
