package Cpanel::API::cPGreyList;

# cpanel - Cpanel/API/cPGreyList.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.0';

use List::Util ();

use Cpanel                         ();    # for 'main::hasfeature' usage
use Cpanel::AdminBin::Call         ();
use Cpanel::GreyList::Config       ();
use Cpanel::Config::userdata::Load ();

my $allow_demo = { allow_demo => 1 };

our %API = (
    _needs_feature          => "greylist",
    _worker_node_type       => 'Mail',
    list_domains            => $allow_demo,
    has_greylisting_enabled => $allow_demo,
);

my $domain_data_cache;

=head1 NAME

Cpanel::API::cPGreyList

=head1 DESCRIPTION

UAPI functions related to GreyList management by cPanel users.

=head2 list_domains

List of domains, with their opt-out status, belonging to the cPanel user.

B<Output>: An array where each item is a hash containing:

    'domain': string - name of the domain
    'enabled': boolean - 1 if greylisting is enabled, 0 if greylisting is disabled
    'dependencies': Other related domains which will be impacted by changes to this domain's enabled/disabled status.
    'searchhint': A comma-separated list of search terms related to this domain, to aid the development of filtering on the caller's side.
    'type': The type of domain. Can be 'main' or 'addon' or 'parked'.

=cut

sub list_domains {
    my ( $args, $result ) = @_;

    my $domains  = _get_domain_data();
    my $enabled  = 0;
    my $disabled = 0;

    my $enabled_status = _enabled_for_domains( [ map { $_->{'domain'} } @{$domains} ] );

    my @results;
    foreach my $domain_hr (@$domains) {
        my $status = $enabled_status->{ $domain_hr->{'domain'} };
        if ($status) {
            $enabled++;
        }
        else {
            $disabled++;
        }
        $domain_hr->{'enabled'} = $status;
        push @results, $domain_hr;
    }

    $result->data( \@results );
    $result->metadata(
        'cPGreyList',
        {
            'total_disabled' => $disabled,
            'total_enabled'  => $enabled,
        }
    );

    return 1;
}

=head2 enable_domains

Enable Greylisting for the requested list of domains belonging to this account.

B<Input>: A list of domains to enable greylisting for (They must belong to your account.)

    'domains-0' => domain0.com
    'domains-1' => domain1.com

B<Output>: An array of hashes, where each hash has the following structure.

    'domain': string - name of the domain
    'enabled': boolean - 1 if greylisting is enabled, 0 if greylisting is disabled
    'type': The type of domain. Can be 'main' or 'addon' or 'parked'.

If an error occurred because any of the domains were invalid, they will be litsed in
an array called B<invalid_domains>.

=cut

sub enable_domains {

    my ( $args, $result ) = @_;
    my @domains = $args->get_args_like(qr/domains(-\d+)?/);

    if ( not scalar @domains ) {
        $result->error('Invalid parameter: You did not provide any domains in the call to enable_domains.');
        $result->data( { 'no_domains_provided' => 1 } );
        return;
    }

    my ( $valid_domains_ar, $invalid_domains_ar ) = _check_domains( \@domains );
    if ( scalar @$invalid_domains_ar ) {
        $result->error( 'The following domains do not belong to your account: [_1]', @$invalid_domains_ar );
        $result->data( { 'invalid_domains_provided' => 1, 'invalid_domains' => $invalid_domains_ar } );
        return;
    }

    Cpanel::AdminBin::Call::call( 'Cpanel', "cpgreylist", "DOMAIN_GREYLIST_ENABLE", @$valid_domains_ar );
    my $enabled_status = _enabled_for_domains($valid_domains_ar);

    my @results;
    foreach my $domain (@$valid_domains_ar) {
        my $data = _get_domain_data_by_domain_name($domain);    # userdata is cached, so repeated calls here are fine.
        $data->{'enabled'} = $enabled_status->{$domain};
        push @results, $data;
    }

    $result->data( \@results );

    return 1;
}

=head2 disable_domains

Disable Greylisting for the requested list of domains belonging to this account.

B<Input>: A list of domains to disable greylisting for (They must belong to your account.)

    'domains-0' => domain0.com
    'domains-1' => domain1.com

B<Output>: An array of hashes, where each hash has the following structure.

    'domain': string - name of the domain
    'enabled': boolean - 1 if greylisting is enabled, 0 if greylisting is disabled
    'type': The type of domain. Can be 'main' or 'addon' or 'parked'.

If an error occurred because any of the domains were invalid, they will be litsed in
an array called B<invalid_domains>.

=cut

sub disable_domains {

    my ( $args, $result ) = @_;
    my @domains = $args->get_args_like(qr/domains(-\d+)?/);

    if ( not scalar @domains ) {
        $result->error('Invalid parameter: You did not provide any domains in the call to disable_domains.');
        $result->data( { 'no_domains_provided' => 1 } );
        return;
    }

    my ( $valid_domains_ar, $invalid_domains_ar ) = _check_domains( \@domains );
    if ( scalar @$invalid_domains_ar ) {
        $result->error( 'The following domains do not belong to your account: [_1]', @$invalid_domains_ar );
        $result->data( { 'invalid_domains_provided' => 1, 'invalid_domains' => $invalid_domains_ar } );
        return;
    }

    Cpanel::AdminBin::Call::call( 'Cpanel', "cpgreylist", "DOMAIN_GREYLIST_DISABLE", @$valid_domains_ar );
    my $enabled_status = _enabled_for_domains($valid_domains_ar);

    my @results;
    foreach my $domain (@$valid_domains_ar) {
        my $data = _get_domain_data_by_domain_name($domain);
        $data->{'enabled'} = $enabled_status->{$domain};
        push @results, $data;
    }

    $result->data( \@results );

    return 1;
}

=head2 enable_all_domains

Enable Greylisting for all the domains belonging to this account.

B<Input>: None.

B<Output>: An array of hashes, where each hash has the following structure.

    'domain': string - name of the domain
    'enabled': boolean - 1 if greylisting is enabled, 0 if greylisting is disabled
    'type': The type of domain. Can be 'main' or 'addon' or 'parked'.

=cut

sub enable_all_domains {

    my ( $args, $result ) = @_;

    my $domains = _get_domain_data();

    my @_domains = map { $_->{'domain'} } @$domains;
    Cpanel::AdminBin::Call::call( 'Cpanel', "cpgreylist", "DOMAIN_GREYLIST_ENABLE", @_domains );
    my $enabled_status = _enabled_for_domains( \@_domains );

    my @results;
    foreach my $domain_hr (@$domains) {
        $domain_hr->{'enabled'} = $enabled_status->{ $domain_hr->{domain} };
        push @results, $domain_hr;
    }

    $result->data( \@results );

    return 1;
}

=head2 disable_all_domains

Disable Greylisting for all the domains belonging to this account.

B<Input>: None.

B<Output>: An array of hashes, where each hash has the following structure.

    'domain': string - name of the domain
    'enabled': boolean - 1 if greylisting is enabled, 0 if greylisting is disabled
    'type': The type of domain. Can be 'main' or 'addon' or 'parked'.

=cut

sub disable_all_domains {

    my ( $args, $result ) = @_;

    my $domains = _get_domain_data();

    my @_domains = map { $_->{'domain'} } @$domains;
    Cpanel::AdminBin::Call::call( 'Cpanel', "cpgreylist", "DOMAIN_GREYLIST_DISABLE", @_domains );
    my $enabled_status = _enabled_for_domains( \@_domains );

    my @results;
    foreach my $domain_hr (@$domains) {
        $domain_hr->{'enabled'} = $enabled_status->{ $domain_hr->{domain} };
        push @results, $domain_hr;
    }

    $result->data( \@results );

    return 1;
}

=head2 has_greylisting_enabled

Check if the Greylisting service is enabled on the server.

B<Input>: None.

B<Output>: A hash that has the following structure.

    'enabled': boolean - 1 if greylisting is enabled, 0 if greylisting is disabled

=cut

sub has_greylisting_enabled {
    my ( $args, $result ) = @_;

    # This does not require root privileges to check
    my $enabled = Cpanel::GreyList::Config::is_enabled();

    $result->data( { 'enabled' => $enabled } );

    return 1;
}

sub _check_domains {
    my $domains_ar    = shift;
    my $valid_domains = _get_domain_data();

    my ( @valid_domains, @invalid_domains );
    foreach my $domain (@$domains_ar) {
        if ( !grep { $_->{'domain'} eq $domain } @$valid_domains ) {
            push @invalid_domains, $domain;
        }
        else {
            push @valid_domains, $domain;
        }
    }

    return ( \@valid_domains, \@invalid_domains );
}

sub _enabled_for_domains {
    my $domains_ar = shift;
    return Cpanel::AdminBin::Call::call( 'Cpanel', "cpgreylist", "DOMAIN_GREYLIST_ENABLED", @{$domains_ar} );
}

sub _get_domain_data_by_domain_name {
    my $domain      = shift;
    my $domain_data = _get_domain_data();
    return List::Util::first { $_->{'domain'} eq $domain } @$domain_data;
}

sub _get_domain_data {
    my $domain_data;

    if ( !$domain_data_cache ) {
        $domain_data_cache = $domain_data = Cpanel::Config::userdata::Load::load_userdata_main($Cpanel::user);
    }
    else {
        $domain_data = $domain_data_cache;
    }

    my @vhosts = ();

    # Remove subdomains tied to addon domains from the deps of the main domains
    my $addon_subdomains = { reverse %{ $domain_data->{'addon_domains'} } };
    my @deps             = sort grep { !exists $addon_subdomains->{$_} && $_ =~ m/\.$domain_data->{'main_domain'}$/ } @{ $domain_data->{'sub_domains'} };
    my $data             = {
        'domain'       => $domain_data->{'main_domain'},
        'type'         => 'main',
        'dependencies' => \@deps,
        'searchhint'   => join( ',', @deps ),
    };
    push( @vhosts, $data );

    foreach my $addon_domain ( keys %{ $domain_data->{'addon_domains'} } ) {
        my $sub  = $domain_data->{'addon_domains'}->{$addon_domain};
        my @deps = ( sort grep { $_ =~ m/\.$addon_domain$/ } @{ $domain_data->{'sub_domains'} }, $sub );
        $data = {
            'domain'       => $addon_domain,
            'type'         => 'addon',
            'dependencies' => \@deps,
            'searchhint'   => join( ',', @deps ),
        };
        push( @vhosts, $data );
    }

    foreach my $parked_domain ( @{ $domain_data->{'parked_domains'} } ) {
        my @deps = sort grep { $_ =~ m/\.$parked_domain$/ } @{ $domain_data->{'sub_domains'} };
        $data = {
            'domain'       => $parked_domain,
            'type'         => 'parked',
            'dependencies' => \@deps,
            'searchhint'   => join( ',', @deps ),
        };
        push( @vhosts, $data );
    }

    # Filter out domains that are in userdata but not on the account
    # because the dns zone may have been deleted.
    my %users_configured_domains = map { $_ => 1 } @Cpanel::DOMAINS;

    @vhosts = grep { $users_configured_domains{ $_->{'domain'} } } sort { $a->{'domain'} cmp $b->{'domain'} } @vhosts;

    return \@vhosts;
}

sub _clear_domain_data_cache {
    undef $domain_data_cache;
    return;
}

1;
