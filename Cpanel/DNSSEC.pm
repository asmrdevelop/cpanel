
# cpanel - Cpanel/DNSSEC.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::DNSSEC;

use cPstrict;

use Try::Tiny;

use Cpanel::Exception ();

=encoding utf-8

=head1 NAME

Cpanel::DNSSEC - Tools for managing DNSSEC

=head1 SYNOPSIS

    use Cpanel::DNSSEC;

    my $results_ar = Cpanel::DNSSEC::enable_dnssec_for_domains( $domains_ar, $nsec_config, $algo_config );
    my $results_ar = Cpanel::DNSSEC::disable_dnssec_for_domains($domains_ar);
    my $results_ar = Cpanel::DNSSEC::fetch_ds_records_for_domains($domains_ar);
    my $results_ar = Cpanel::DNSSEC::set_nsec3_for_domains( $domains_ar, $nsec_config );
    my $results_ar = Cpanel::DNSSEC::unset_nsec3_for_domains($domains_ar);
    my $results_hr = Cpanel::DNSSEC::activate_zone_key( $domain, $key_id );
    my $results_hr =  Cpanel::DNSSEC::deactivate_zone_key( $domain, $key_id );
    my $results_hr =  Cpanel::DNSSEC::add_zone_key( $domain, $algo_config );
    my $results_hr =  Cpanel::DNSSEC::remove_zone_key( $domain, $key_id );
    my $results_hr =  Cpanel::DNSSEC::import_zone_key( $domain, $key_data, $key_type );
    my $results_hr =  Cpanel::DNSSEC::export_zone_key( $domain, $key_id );

=head1 DESCRIPTION

This module is the underlying guts for Cpanel::Admin::Modules::Cpanel::dnssec
and the DNSSEC functions in Whostmgr::API::1::DNS.

=head1 WARNINGS

Do not change the return structures of this module as Whostmgr::API::1::DNS
treats it as a thin wrapper and changes to the returns will be passed directly
to WHMAPI1 responses.

=head1 FUNCTIONS

=head2 enable_dnssec_for_domains( $domains_ar, $nsec_config, $algo_config )

Enable DNSSEC for a list of domains.

=over 2

=item Input

=over 3

=item $domain_ar C<ARRAYREF>

An arrayref of domains

=item $nsec_config C<HASHREF> (optional)

An NSEC3 config hashref. See See C<Cpanel::NameServer::Conf::PowerDNS::algo_config_defaults>
and C<Cpanel::NameServer::Conf::PowerDNS::validate_nsec3_config>

=item $algo_config C<HASHREF> (optional)

An algorithm parameters hashref. See C<Cpanel::NameServer::Conf::PowerDNS::algo_config_defaults>
and C<Cpanel::NameServer::Conf::PowerDNS::validate_algo_config>

=back

=item Output

=over 3

=item C<ARRAYREF> of C<HASHREF>

An arrayref of hashrefs with the DNSSEC status of each domain is
returned in the following format:

    [
        {'domain' => $domain, 'enabled' => 1, 'nsec_version' => $nsec_version, 'new_key_id' => $new_key_id, 'nsec_error' => $nsec_error},
        {'domain' => $domain, 'enabled' => 0, 'error' => $error},
        ...
    ]

If there an an error enabling DNSSEC, enabled is set to 0 and the error is found in the error key.

If there is an error with the NSEC3 configuration, the nsec_version will be set to NSEC and the error
can be found in the nsec_error key.

=back

=back

=cut

sub enable_dnssec_for_domains ( $domains_ar, $nsec_config, $algo_config ) {    ## no critic qw(Proto Subroutines::ProhibitManyArgs) -- misparse
    _validate_domains($domains_ar);

    my $dns_obj = _get_dns_obj();

    $algo_config = $dns_obj->algo_config_defaults($algo_config);
    $nsec_config = $dns_obj->nsec_config_defaults($nsec_config);

    my $validated_algo_config = $dns_obj->validate_algo_config($algo_config);     # throws exception on invalid configuration
    my $validated_nsec_config = $dns_obj->validate_nsec3_config($nsec_config);    # also throws

    my @results;
    foreach my $domain ( @{$domains_ar} ) {
        local $@;
        my $secure_zone = eval { $dns_obj->secure_zone( $validated_algo_config, $domain ); };
        my $result_hr   = { 'domain' => $domain };
        if ( $secure_zone && $secure_zone->{'id'} ) {

            $result_hr->{'enabled'}      = 1;
            $result_hr->{'nsec_version'} = 'NSEC';
            $result_hr->{'new_key_id'}   = $secure_zone->{'id'};

            if ( $validated_nsec_config->{'use_nsec3'} ) {

                # Calling set_nsec3 will always result in a call to
                # rectify the zone if set_nsec3 is successful.  Since
                # we need to call rectify after a set_nec3 or secure_zone,
                # calling set_nsec3 will take care of this.
                my $set_nsec3 = $dns_obj->set_nsec3( $domain, $validated_nsec_config );

                if ( $set_nsec3->{'success'} ) {
                    $result_hr->{'nsec_version'} = 'NSEC3';
                }
                else {
                    $result_hr->{'nsec_error'} = $set_nsec3->{'error'};
                }
            }
            else {
                eval { $dns_obj->rectify($domain) };

                # We did not enable nsec3 so we do the rectify
                # ourselves.  There is not way to report partial
                # success so we set error here so at least its not lost
                if ($@) {
                    $result_hr->{'error'} = $@;
                }
            }
        }
        else {
            $result_hr->{'enabled'} = 0;
            $result_hr->{'error'}   = $secure_zone ? $secure_zone->{'error'} : $@;
        }
        push @results, $result_hr;
    }

    return \@results;
}

=head2 disable_dnssec_for_domains( $domains_ar )

Disable DNSSEC for a list of domains.

=over 2

=item Input

=over 3

=item $domain_ar C<ARRAYREF>

An arrayref of domains

=back

=item Output

=over 3

=item C<ARRAYREF> of C<HASHREF>

An arrayref of hashrefs with the DNSSEC status of each domain is
returned in the following format:

    [
        {'domain' => $domain, 'disabled' => 1},
        {'domain' => $domain, 'disabled' => 0, 'error' => $error},
        ...
    ]

If there an an error disabling DNSSEC, disabled is set to 0 and the error is found in the error key.

=back

=back

=cut

sub disable_dnssec_for_domains ($domains_ar) {
    _validate_domains($domains_ar);

    my $dns_obj = _get_dns_obj();

    my @results;
    foreach my $domain ( @{$domains_ar} ) {
        local $@;
        my $unsecure_zone = eval { $dns_obj->unsecure_zone($domain) };
        my $result        = { 'domain' => $domain, 'disabled' => $unsecure_zone ? 1 : 0 };
        $result->{error} = $@ if $@;
        push( @results, $result );
    }

    return \@results;
}

=head2 fetch_ds_records_for_domains( $domains_ar )

Fetch DS records for a list of domains.

=over 2

=item Input

=over 3

=item $domain_ar C<ARRAYREF>

An arrayref of domains

=back

=item Output

=over 3

=item C<ARRAYREF> of C<HASHREF>

An arrayref of hashrefs with the DS records for each domain

    [
        {'domain' => $domain, 'ds_records' => $records},
        {'domain' => $domain, 'ds_records' => {}},
        ...
    ]

If there are no DS records for a given domain ds_records will be an empty hashref.

=back

=back

=cut

sub fetch_ds_records_for_domains ($domains_ar) {
    _validate_domains($domains_ar);
    my $dns_obj = _get_dns_obj();

    return [
        map {
            (
                {
                    domain => $_,

                    # CPANEL-30781: errors from this call are suppressed as the callers already
                    # do an existence check for the domains, and the errors reported from powerdns
                    # are usually a result of subdomains being queried.
                    ds_records => ( try { $dns_obj->ds_records($_) } ) // {},
                }
            )
        } @{$domains_ar}
    ];
}

=head2 set_nsec3_for_domains( $domains_ar, $nsec_config )

Setup NSEC3 records for a list of domains.

=over 2

=item Input

=over 3

=item $domain_ar C<ARRAYREF>

An arrayref of domains

=item $nsec_config C<HASHREF> (optional)

An NSEC3 config hashref. See See C<Cpanel::NameServer::Conf::PowerDNS::algo_config_defaults>
and C<Cpanel::NameServer::Conf::PowerDNS::validate_nsec3_config>

This is the same hashref format that C<enable_dnssec_for_domains> consumes.

=back

=item Output

=over 3

=item C<ARRAYREF> of C<HASHREF>

An arrayref of hashrefs with the NSEC3 status of each domain is
returned in the following format:

    [
        {'domain' => $domain, 'enabled' => 1},
        {'domain' => $domain, 'enabled' => 0, 'error' => $error},
        ...
    ]

If there an an error enabling NSEC3, enabled is set to 0 and the error is found in the error key.

=back

=back

=cut

sub set_nsec3_for_domains ( $domains_ar, $nsec_config ) {
    _validate_domains($domains_ar);

    my $dns_obj = _get_dns_obj();

    $nsec_config = $dns_obj->nsec_config_defaults($nsec_config);
    my $validated_nsec_config = $dns_obj->validate_nsec3_config($nsec_config);

    my @results;
    foreach my $domain ( @{$domains_ar} ) {
        my $set_nsec3 = $dns_obj->set_nsec3( $domain, $validated_nsec_config );

        if ( $set_nsec3->{'success'} ) {
            push @results, { 'domain' => $domain, 'enabled' => 1 };
        }
        else {
            push @results, { 'domain' => $domain, 'enabled' => 0, 'error' => $set_nsec3->{'error'} };
        }
    }

    return \@results;
}

=head2 unset_nsec3_for_domains( $domains_ar )

Disable NSEC3 for a list of domains.

=over 2

=item Input

=over 3

=item $domain_ar C<ARRAYREF>

An arrayref of domains

=back

=item Output

=over 3

=item C<ARRAYREF> of C<HASHREF>

An arrayref of hashrefs with the NSEC3 status of each domain is
returned in the following format:

    [
        {'domain' => $domain, 'disabled' => 1},
        {'domain' => $domain, 'disabled' => 0, 'error' => $error},
        ...
    ]

If there an an error disabling NSEC3, disabled is set to 0 and the error is found in the error key.

=back

=back

=cut

sub unset_nsec3_for_domains ($domains_ar) {
    _validate_domains($domains_ar);

    my $dns_obj = _get_dns_obj();

    my @results;
    foreach my $domain ( @{$domains_ar} ) {
        my $unset_nsec3 = $dns_obj->unset_nsec3($domain);
        if ( $unset_nsec3->{'success'} ) {
            push @results, { 'domain' => $domain, 'disabled' => 1 };
        }
        else {
            push @results, { 'domain' => $domain, 'disabled' => 0, 'error' => $unset_nsec3->{'error'} };
        }
    }

    return \@results;
}

=head2 activate_zone_key( $domain, $key_id )

Activates a DNSSEC key id.

=over 2

=item Input

=over 3

=item $domain C<SCALAR>

The C<$domain> is the domain to modify.

=item $key_id C<SCALAR>

The C<$key_id> is the ID of the key to activate.

=back

=item Output

=over 3

=item C<HASHREF>

A hashrefs in the following format:

    {
        'key_id'  => $key_id,
        'domain'  => $domain,
        'success' => 1,
    }

If the success field is set to 0, and error
field will be included with the reason for the
error:


    {
        'key_id'  => $key_id,
        'domain'  => $domain,
        'success' => 0,
        'error' => $error
    }

=back

=back

=cut

sub activate_zone_key ( $domain, $key_id ) {
    return _call_zone_key_function( 'activate_zone_key', $domain, $key_id );
}

=head2 deactivate_zone_key( $domain, $key_id )

Dectivates a DNSSEC key id.

=over 2

=item Input

=over 3

=item $domain C<SCALAR>

The C<$domain> is the domain to modify.

=item $key_id C<SCALAR>

The C<$key_id> is the ID of the key to deactivate.

=back

=item Output

=over 3

=item C<HASHREF>

A hashrefs in the following format:

    {
        'key_id'  => $key_id,
        'domain'  => $domain,
        'success' => 1,
    }

If the success field is set to 0, and error
field will be included with the reason for the
error:


    {
        'key_id'  => $key_id,
        'domain'  => $domain,
        'success' => 0,
        'error' => $error
    }

=back

=back

=cut

sub deactivate_zone_key ( $domain, $key_id ) {
    return _call_zone_key_function( 'deactivate_zone_key', $domain, $key_id );
}

=head2 add_zone_key( $domain, $algo_config )

Adds a new DNSSEC key for the specified C<$domain>, using the
configuration specified in C<$algo_config>.

=over 2

=item Input

=over 3

=item $domain C<SCALAR>

The C<$domain> is the domain to modify.

=item $algo_config C<HASHREF>

An algorithm parameters hashref. See C<Cpanel::NameServer::Conf::PowerDNS::algo_config_defaults>
and C<Cpanel::NameServer::Conf::PowerDNS::validate_algo_config>

=back

=item Output

=over 3

=item C<HASHREF>

A hashrefs in the following format:

    {
        'new_key_id'  => $key_id,
        'domain'  => $domain,
        'success' => 1,
    }

If the success field is set to 0, and error
field will be included with the reason for the
error:


    {
        'domain'  => $domain,
        'success' => 0,
        'error' => $error
    }

=back

=back

=cut

sub add_zone_key ( $domain, $algo_config ) {
    _validate_domain($domain);
    my $dns_obj          = _get_dns_obj();
    my $valid_key_config = $dns_obj->generate_key_config_based_on_algo_num_and_key_type($algo_config);    # dies on invalid input

    my $add = $dns_obj->add_zone_key( $domain, $valid_key_config );

    return {
        'domain'  => $domain,
        'success' => $add->{'id'} ? 1 : 0,
        ( $add->{'id'}  && $add->{'id'}    ? ( 'new_key_id' => $add->{'id'} )    : () ),
        ( !$add->{'id'} && $add->{'error'} ? ( 'error'      => $add->{'error'} ) : () ),
    };
}

=head2 remove_zone_key( $domain, $key_id )

Removes a DNSSEC key for a domain.

=over 2

=item Input

=over 3

=item $domain C<SCALAR>

The C<$domain> is the domain to modify.

=item $key_id C<SCALAR>

The ID of the key to remove.  The C<fetch_ds_records_for_domains>
method can be used to find the key ID.

=back

=item Output

=over 3

=item C<HASHREF>

A hashrefs in the following format:

    {
        'key_id'  => $key_id,
        'domain'  => $domain,
        'success' => 1,
    }

If the success field is set to 0, and error
field will be included with the reason for the
error:


    {
        'domain'  => $domain,
        'success' => 0,
        'error' => $error
    }

=back

=back

=cut

sub remove_zone_key ( $domain, $key_id ) {
    _validate_domain($domain);
    _validated_key_id($key_id);

    my $remove = _get_dns_obj()->remove_zone_key( $domain, $key_id );

    return {
        'key_id'  => $key_id,
        'domain'  => $domain,
        'success' => $remove->{'success'} ? 1 : 0,
        ( !$remove->{'success'} && $remove->{'error'} ? ( 'error' => $remove->{'error'} ) : () ),
    };
}

=head2 import_zone_key( $domain, $key_data, $key_type  )

Import a DNSSEC key for a domain.

=over 2

=item Input

=over 3

=item $domain C<SCALAR>

The C<$domain> is the domain to modify.

=item $key_data C<SCALAR>

The C<$key_data> is a string containing the DNSSEC key in the ICS format that PowerDNS recognizes.

=item $key_type C<SCALAR>

The C<$key_type> is the key type (KSK or ZSK) to use when importing.

=back

=item Output

=over 3

=item C<HASHREF>

A hashrefs in the following format:

    {
        'new_key_id'  => $key_id,
        'domain'  => $domain,
        'success' => 1,
    }

If the success field is set to 0, and error
field will be included with the reason for the
error:


    {
        'domain'  => $domain,
        'success' => 0,
        'error' => $error
    }

=back

=back

=cut

sub import_zone_key ( $domain, $key_data, $key_type ) {
    _validate_domain($domain);
    die Cpanel::Exception::create( 'MissingParameter', 'Provide the “[_1]” argument.', ['key_data'] )
      if !length $key_data;
    die Cpanel::Exception::create( 'MissingParameter', 'Provide the “[_1]” argument.', ['key_type'] )
      if !length $key_type;
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be one of the following: [join,~, ,_2]', [ 'key_type', [ 'ksk', 'zsk' ] ] )
      if $key_type !~ m/^(?:[kz]sk)$/i;

    my $new_key_id;
    my $import = _get_dns_obj()->import_zone_key( $domain, $key_data, $key_type );

    chomp( $new_key_id = $import->{'new_key_id'} )
      if $import->{'new_key_id'};

    return {
        'domain'  => $domain,
        'success' => $import->{'new_key_id'} ? 1 : 0,
        ( $import->{'new_key_id'}  && $new_key_id        ? ( 'new_key_id' => $new_key_id )        : () ),
        ( !$import->{'new_key_id'} && $import->{'error'} ? ( 'error'      => $import->{'error'} ) : () ),
    };
}

=head2 export_zone_key( $domain, $key_id  )

Export a DNSSEC key for a domain.

=over 2

=item Input

=over 3

=item $domain C<SCALAR>

The C<$domain> is the domain to modify.

=item $key_id C<SCALAR>

The ID of the key to remove.  The C<fetch_ds_records_for_domains>
method can be used to find the key ID.

=back

=item Output

=over 3

=item C<HASHREF>

A hashrefs in the following format:

    {
        'key_id'  => $key_id,
        'key_tag'  => $key_tag,
        'key_type'  => $key_type,
        'key_content'  => $key_content,
        'domain'  => $domain,
        'success' => 1,
    }

If the success field is set to 0, and error
field will be included with the reason for the
error:


    {
        'key_id'  => $key_id,
        'key_tag'  => $key_tag,
        'key_type'  => $key_type,
        'domain'  => $domain,
        'success' => 0,
        'error' => $error
    }

For more information on the key_* fields see the manual for C<pdnsutil>'s
export-zone-key function.

=back

=back

=cut

sub export_zone_key ( $domain, $key_id ) {
    _validate_domain($domain);
    _validated_key_id($key_id);

    my $ns_obj     = _get_dns_obj();
    my $ds_records = $ns_obj->ds_records($domain);
    if ( my ($key_to_export) = grep { $_->{'key_id'} eq $key_id } ( values %{ $ds_records->{'keys'} } ) ) {

        my $export = $ns_obj->export_zone_key( $domain, $key_id );

        return {
            'key_id'   => $key_id,
            'key_tag'  => $key_to_export->{'key_tag'},
            'key_type' => $key_to_export->{'key_type'},
            'domain'   => $domain,
            'success'  => $export->{'success'},
            (
                $export->{'success'}
                ? ( 'key_content' => $export->{'output'} )
                : ( 'error' => $export->{'error'} // "Unknown error" ),
            ),
        };
    }
    die Cpanel::Exception::create( 'InvalidParameter', 'Invalid key_id or domain specified: No such key present for domain' );
}

=head2 export_zone_dnskey( $domain, $key_id  )

Exports the public DNSKEY for a domain.

=over 2

=item Input

=over 3

=item $domain C<SCALAR>

The C<$domain> is the domain to modify.

=item $key_id C<SCALAR>

The ID of the key that you want to get the DNSKEY for.

=back

=item Output

=over 3

=item C<HASHREF>

A hashrefs in the following format:

    {
        'key_id'  => $key_id,
        'dnskey'  => $dnskey,
        'success' => 1,
    }

If the success field is set to 0, and error
field will be included with the reason for the
error:


    {
        'key_id'  => $key_id,
        'success' => 0,
        'error' => $error
    }

For more information on the key_* fields see the manual for C<pdnsutil>'s
export-zone-dnskey function.

=back

=back

=cut

sub export_zone_dnskey ( $domain, $key_id ) {
    _validate_domain($domain);
    _validated_key_id($key_id);

    my $ns_obj = _get_dns_obj();
    my $dnskey = $ns_obj->export_zone_dnskey( $domain, $key_id );

    return {
        'key_id'  => $key_id,
        'success' => $dnskey->{'success'},
        (
            $dnskey->{'success'}
            ? ( 'dnskey' => $dnskey->{'dnskey'} )
            : ( 'error' => $dnskey->{'error'} // "Unknown error" ),
        ),
    };
}

sub _call_zone_key_function ( $activate_or_deactivate, $domain, $key_id ) {    ## no critic qw(Proto Subroutines::ProhibitManyArgs) - misparse by perlcritic
    _validate_domain($domain);
    _validated_key_id($key_id);

    my $ret = _get_dns_obj()->$activate_or_deactivate( $domain, $key_id );

    return {
        'key_id'  => $key_id,
        'domain'  => $domain,
        'success' => $ret->{'success'} ? 1 : 0,
        ( !$ret->{'success'} && $ret->{'error'} ? ( 'error' => $ret->{'error'} ) : () ),
    };
}

sub _validate_domain ($domain) {
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'domain' ] )    # This bubbles up to the apis that require a domain
      if !length $domain;
    require Cpanel::Validate::Domain;
    Cpanel::Validate::Domain::valid_rfc_domainname_or_die($domain);
    return 1;
}

sub _validate_domains ($domains_ar) {
    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'domain' ] )    # This bubbles up to the apis that require a domain

      if !@$domains_ar;
    require Cpanel::Validate::Domain;
    Cpanel::Validate::Domain::valid_rfc_domainname_or_die($_) for @$domains_ar;
    return 1;
}

sub _get_dns_obj {
    require Cpanel::NameServer::Conf;

    my $dns_obj = Cpanel::NameServer::Conf->new();
    die Cpanel::Exception->create('[asis,DNSSEC] is only supported on servers configured with [asis,PowerDNS].')
      if $dns_obj->type() ne 'powerdns';

    return $dns_obj;
}

sub _validated_key_id {
    my $key_id = shift;

    die Cpanel::Exception::create( 'MissingParameter', 'Provide the “[_1]” argument.', ['key_id'] )
      if !length $key_id;
    die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” must be a positive integer.', ['key_id'] )
      if $key_id !~ /\A[1-9][0-9]*\z/;

    return 1;
}

1;
