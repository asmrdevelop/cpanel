package Cpanel::WebCalls::Type::DynamicDNS;

# cpanel - Cpanel/WebCalls/Type/DynamicDNS.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Type::DynamicDNS

=head1 SYNOPSIS

See the base class.

=head1 DESCRIPTION

This module implements the C<DynamicDNS> webcall.
It subclasses L<Cpanel::WebCalls::Type>.

=cut

# one-liner for testing:
# > perl -Mstrict -w -MCpanel::PromiseUtils -MCpanel::WebCalls::Datastore::Write -e'my $obj = Cpanel::PromiseUtils::wait_anyevent( Cpanel::WebCalls::Datastore::Write->new_p( timeout => 30) )->get(); $obj->create_for_user("cpssltest", "DynamicDNS", { domain => "home.cpanelssltest.org" })'

#----------------------------------------------------------------------

use parent 'Cpanel::WebCalls::Type';

use Cpanel::Imports;

use Cpanel::Set ();

use Cpanel::WebCalls::Type::DynamicDNS::Backend ();

my @good_data = ( 'domain', 'description' );

my @good_run_args = ( 'ipv4', 'ipv6' );

my @good_update_args = ('description');

my $_TTL = 300;

#----------------------------------------------------------------------

sub _WHY_ENTRY_DATA_INVALID ( $, $username, $data_hr ) {
    return "must be a hashref" if 'HASH' ne ref $data_hr;

    my @bad = Cpanel::Set::difference(
        [ keys %$data_hr ],
        \@good_data,
    );

    if (@bad) {
        return "Unrecognized: @bad";
    }

    my $why = Cpanel::WebCalls::Type::DynamicDNS::Backend::why_description_invalid( $data_hr->{'description'} );

    my $domain = $data_hr->{'domain'};

    $why ||= Cpanel::WebCalls::Type::DynamicDNS::Backend::why_domain_alone_invalid($domain);

    if ( !$why && Cpanel::WebCalls::Type::DynamicDNS::Backend::is_dupe_domain( $username, $domain ) ) {
        $why = locale()->maketext( "“[_1]” is already a dynamic [asis,DNS] domain.", $domain );
    }

    $why ||= Cpanel::WebCalls::Type::DynamicDNS::Backend::why_user_and_domain_invalid( $username, $domain );

    return $why;
}

sub _WHY_UPDATE_DATA_INVALID ( $, $username, $data_hr ) {
    return "must be a hashref" if 'HASH' ne ref $data_hr;

    my @bad = Cpanel::Set::difference(
        [ keys %$data_hr ],
        \@good_update_args,
    );

    if (@bad) {
        return "Unrecognized: @bad";
    }

    my $why = Cpanel::WebCalls::Type::DynamicDNS::Backend::why_description_invalid( $data_hr->{'description'} );

    return $why;
}

sub _NORMALIZE_ENTRY_DATA ( $, $username, $data_hr ) {
    return "must be a hashref" if 'HASH' ne ref $data_hr;

    my @bad = Cpanel::Set::difference(
        [ keys %$data_hr ],
        \@good_data,
    );

    if (@bad) {
        return "Unrecognized: @bad";
    }

    my $domain = $data_hr->{'domain'};

    require Cpanel::Validate::Domain::Normalize;
    $domain = Cpanel::Validate::Domain::Normalize::normalize( $domain, 1 );

    $data_hr->{'domain'} = $domain;

    return;
}

sub _WHY_RUN_ARGUMENTS_INVALID ( $, @args_array ) {
    if ( @args_array % 2 ) {
        return 'args list must be even';
    }

    my %input = @args_array;

    my @bad = Cpanel::Set::difference(
        [ keys %input ],
        \@good_run_args,
    );

    if (@bad) {
        return "unrecognized: @bad (args may be: @good_run_args)";
    }

    if (%input) {
        my $ip = $input{'ipv4'};
        if ( length $ip ) {
            require Cpanel::Validate::IP::v4;
            if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
                return locale()->maketext( "“[_1]” is not a valid [asis,IPv4] address.", $ip );
            }
        }

        $ip = $input{'ipv6'};

        if ( length $ip ) {
            require Cpanel::Validate::IP;
            if ( !Cpanel::Validate::IP::is_valid_ipv6($ip) ) {
                return return locale()->maketext( "“[_1]” is not a valid [asis,IPv6] address.", $ip );
            }
        }
    }
    elsif ( !$ENV{'REMOTE_ADDR'} ) {

        # $ENV{'REMOTE_ADDR'} should be defined *any* time the webcall
        # runs; however, we only need to care about that in the case
        # where no explicit address is given. Since this case represents
        # an internal abnormality rather than a bad request, we report
        # this failure to the caller as an internal error rather than
        # describing the specific problem.
        #
        require Carp;
        Carp::confess("No REMOTE_ADDR in the environment!");
    }

    return undef;
}

sub _RUN ( $class, $id, $entry_obj, %input ) {

    _populate_from_env_if_needed( \%input );

    my $needs_update = Cpanel::WebCalls::Type::DynamicDNS::Backend::needs_update(
        $id,
        $entry_obj,
        \%input,
    );

    # Normalize IPv6 if needed
    if ( my $ip = $input{'ipv6'} ) {
        require Cpanel::IPv6::RFC5952;
        $input{'ipv6'} = Cpanel::IPv6::RFC5952::convert($ip);
    }

    if ($needs_update) {

        my @records;

        my $domain = $entry_obj->domain();

        if ( my $ip = $input{'ipv4'} ) {
            push @records, [ $domain => 'A', $ip ];
        }

        if ( my $ip = $input{'ipv6'} ) {
            push @records, [ $domain => 'AAAA', $ip ];
        }

        require Cpanel::DnsUtils::Batch;

        Cpanel::DnsUtils::Batch::set( \@records, $_TTL );
    }

    my $rettype = $needs_update ? '_UPDATED' : '_RAN';

    my $description = join(
        '; ',
        map { "$_: $input{$_}" } sort keys %input,
    );

    return $class->$rettype(), $description;
}

sub _IS_DATA_EQUAL ( $class, $data1, $data2 ) {

    return 0 if !$data1->{description} && $data2->{description};
    return 0 if $data1->{description}  && !$data2->{description};
    return 0 if $data1->{description}  && $data2->{description} && $data1->{description} ne $data2->{description};

    return 0 if !$data1->{domain} && $data2->{domain};
    return 0 if $data1->{domain}  && !$data2->{domain};
    return 0 if $data1->{domain}  && $data2->{domain} && $data1->{domain} ne $data2->{domain};

    return 1;
}

sub _MERGE_DATA ( $class, $starting_data, $new_data ) {
    my $merged_data = $class->create_data_copy($starting_data);
    $merged_data->{'domain'}      = $new_data->{'domain'}      if defined $new_data->{'domain'};
    $merged_data->{'description'} = $new_data->{'description'} if defined $new_data->{'description'};
    return $merged_data;
}

sub _ON_POST_DELETE ( $, $entry_obj ) {
    require Cpanel::DnsUtils::Batch;
    Cpanel::DnsUtils::Batch::unset(
        [
            [ $entry_obj->domain(), 'A' ],
            [ $entry_obj->domain(), 'AAAA' ],
        ]
    );

    return;
}

#----------------------------------------------------------------------

sub _populate_from_env_if_needed ($ips_hr) {
    if ( !%$ips_hr ) {
        my $remote_ip = _get_remote_ip_from_env();

        my $key = ( $remote_ip =~ tr<:><> ) ? 'ipv6' : 'ipv4';

        $ips_hr->{$key} = $remote_ip;
    }

    return;
}

sub _get_remote_ip_from_env() {

    # cpsrvd’s REMOTE_ADDR always indicates the client address, even if the
    # immediate socket connection is from httpd (i.e., a reverse proxy).
    #
    # The failure case here should never happen in production since
    # _why_run_arguments_invalid() above already catches it.
    #
    my $addr = $ENV{'REMOTE_ADDR'} // die 'no REMOTE_ADDR set!';

    return $addr;
}

1;
