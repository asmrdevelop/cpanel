package Cpanel::DnsUtils::Install::Template;

# cpanel - Cpanel/DnsUtils/Install/Template.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Install::Template - A template system for DnsUtils::Install

=head1 SYNOPSIS

    use Cpanel::DnsUtils::Install::Template ();

    my $cache_hr = {}; # reuse between multiple template objects
    my $template_obj = Cpanel::DnsUtils::Install::Template->new(
        {'domain'=>'pig.org'}
        $cache_hr
    );

    my $value = $template_obj->process("%domain%. IN A %ip%");

    my $ip = $template_obj->get_key('ip');
    my $domain = $template_obj->get_key('domain');

=head1 DESCRIPTION

This template system is designed to fill in the %domain% and
%ip% values in record operations that are passed to
Cpanel::DnsUtils::Install functions.

=head2 new($data_hr, $install_processor_cache)

Create a template object using the domain data from a
Cpanel::DnsUtils::Install call.

$data_hr should be a hashref with a domain key set to
the value of the domain.

$install_processor_cache_hr is a hashref that stores
the cache that can be reused between
Cpanel::DnsUtils::Install::Template objects

=cut

sub new {
    my ( $class, $data_hr, $install_processor_cache_hr ) = @_;

    if ( !$data_hr->{'domain'} ) {
        die "A Cpanel::DnsUtils::Install::Template requires a 'domain' key;";
    }
    elsif ( !$install_processor_cache_hr ) {
        die "A Cpanel::DnsUtils::Install::Template requires the Cpanel::DnsUtils::Install::Processor cache";
    }

    return bless { 'data_hr' => $data_hr, 'install_processor_cache' => $install_processor_cache_hr }, $class;
}

=head2 process($template_text)

Fill in %ip% and %domain% values with the data
provided when the object was created.

$template_text can be an arrayref of text
to be processed or a scalar of text to be processed.

=cut

sub process {
    my ( $self, $template_text ) = @_;

    return undef if !defined $template_text;

    my $data_hr = $self->{'data_hr'};

    # Template is an arrayref
    if ( ref $template_text ) {
        my @result;
        foreach my $part (@$template_text) {
            if ( index( $part, '%' ) == -1 ) {
                push @result, $part;
                next;
            }

            $self->_fill_ip_in_data() if index( $part, '%ip%' ) > -1 && !$data_hr->{'ip'};

            push @result, $part =~ s/\%([^%]+)\%/$data_hr->{$1}/gr;
        }
        return \@result;
    }

    # Template is a scalar
    if ( index( $template_text, '%' ) == -1 ) {
        return $template_text;
    }

    $self->_fill_ip_in_data() if index( $template_text, '%ip%' ) > -1 && !$data_hr->{'ip'};

    return $template_text =~ s/\%([^%]+)\%/$data_hr->{$1}/gr;

}

=head2 get_key($key)

Processes the data provided when the object was created.

This returns the value of the requested key.

Currently the valid keys are: ip and domain

=cut

sub get_key {
    my ( $self, $key ) = @_;

    my $data_hr = $self->{'data_hr'};
    if ( $key eq 'ip' && !$data_hr->{'ip'} ) {
        $self->_fill_ip_in_data();
    }

    return $data_hr->{$key};
}

sub _fill_ip_in_data {
    my ($self) = @_;
    require Cpanel::NAT;
    require Cpanel::DomainIp;
    $self->{'data_hr'}->{'ip'} = (
        $self->{'install_processor_cache'}->{'_domain_to_ip_cache'}{ $self->{'data_hr'}->{'domain'} } ||= Cpanel::NAT::get_public_ip(    #
            Cpanel::DomainIp::getdomainip(                                                                                               #
                $self->{'data_hr'}->{'domain'},                                                                                          #
            )                                                                                                                            #
        )
    );                                                                                                                                   #
    return;

}

1;
