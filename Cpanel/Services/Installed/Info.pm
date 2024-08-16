package Cpanel::Services::Installed::Info;

# cpanel - Cpanel/Services/Installed/Info.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#This is a helper/accessor object for Cpanel::Services::get_installed_service_info_by_name.

#There is some significant services configuration difference between the different services and it seems the
#results have never been normalized. So rather than try to make getters for every variant, I used automated
#getters and setters so that all the developer has to know is what piece of data they want and ask for it
#by name. If it exists, it will be returned, if it is undef or does not exist, it will be returned as undef
use vars '$AUTOLOAD';

sub new {
    my $class        = shift;
    my $service_info = shift;
    my $self         = bless { 'service' => $service_info }, $class;
    if ( defined($service_info) ) {
        $self->_parse_obj($service_info);
        return $self;
    }
    else {
        return undef;
    }
}

sub get_keys {
    my $self        = shift;
    my @sorted_keys = sort { $a cmp $b } @{ $self->{'valid_config_keys'} };
    return \@sorted_keys;
}

sub get_values {
    my $self   = shift;
    my $values = [];
    foreach my $key ( @{ $self->get_keys() } ) {
        unshift @$values, $self->{'service'}->{$key};
    }
    return $values;
}

sub _parse_obj {
    my $self         = shift;
    my $service_info = shift;
    $self->{'valid_config_keys'} = [];
    foreach my $key ( keys %{$service_info} ) {
        $self->$key = $service_info->{$key};
        push @{ $self->{'valid_config_keys'} }, $key;
    }
    return $self;
}

sub AUTOLOAD : lvalue {    ## no critic qw(Subroutines::RequireFinalReturn) -- lvalue subroutines do not have a return
    my ($self) = shift;
    $AUTOLOAD =~ s/.*://;
    @_ ? $self->{$AUTOLOAD} = shift : !defined( $self->{$AUTOLOAD} ) ? $self->{$AUTOLOAD} = undef : $self->{$AUTOLOAD};
}

1;

=head1 NAME

Cpanel::Services::Installed::Info

=head1 SYNOPSIS

    use $accessor_object = Cpanel::Services::Installed::Info->new($get_installed_services_state_hash)

=head1 DESCRIPTION

L<Cpanel::Services::Installed::Info> is a helper/accessor object for Cpanel::Services::get_installed_service_info_by_name. It takes one
of the datastructrues from the array of datastructures oupup by Cpanel::Services::Installed::State::get_installed_services_state();
and delivered as an argument by the method get_installed_service_info_by_name in the package Cpanel::Services.
Once consumed, it will create the getters so that when calling the key name as a method, it will return the value
that was sent in the datastructure.


=head1 REQUIRES

 vars '$AUTOLOAD'
 facilitates the automatic creation of the getter methods depending on the key->value pairs contained
 in the original submitted argument

=cut

=head1 CLASS METHODS

=head2 new

 $self->new($serviceDatastructure);
 This returns an instance of the Info object. If it is called without an argument, it returns undefiined.
 If it is called with one of the hashes from get_installed_services_state(), it will return an object that is
 ready to return values. Use the returned object by calling any of the configuration keys as a method such as $new_obj->('config_key');.

=head2 get_keys

 $self->get_keys();
 This returns the alphanumerically sorted list of keys in the configuration that was sent at instantiation time.

=head2 get_values

 $self->get_values();
 This returns the values referred to by the keys in alphanumeric order according to keys.

=cut

=head1 SUBROUTINES

=head2 AUTOLOAD

 $self->AUTOLOAD();
 This private method is the autowiring tool that automatically creates the getters at instantiation time.
 This should not be called by the user.

=head2 _parse_obj

 $self->_parse_object($service_info);
 This private method parses a service info object passed to it and creates the methods through the AUTOLOAD process and
 sets up the arrays for get_keys and get_values.

=cut

