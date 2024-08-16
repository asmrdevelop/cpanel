package Cpanel::API::ModSecurity;

# cpanel - Cpanel/API/ModSecurity.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#use warnings;

our $VERSION = '1.0';

#-------------------------------------------------------------------------------------------------
# Purpose:  This module contains the API calls and support code related to the mod_security
# applications available in cPanel.
#-------------------------------------------------------------------------------------------------

# Cpanel Dependencies
use Cpanel                          ();
use Cpanel::AdminBin::Call          ();
use Cpanel::Config::userdata::Cache ();
use Cpanel::Locale 'lh';
use Cpanel::Logger                 ();
use Cpanel::ModSecurity            ();
use Cpanel::Config::userdata::Load ();

my $modsecurity_feature_allow_demo = { needs_feature => "modsecurity", allow_demo => 1 };
my $modsecurity_feature_deny_demo  = { needs_feature => "modsecurity" };

our %API = (
    _needs_role               => 'WebServer',
    list_domains              => $modsecurity_feature_allow_demo,
    enable_domains            => $modsecurity_feature_deny_demo,
    disable_domains           => $modsecurity_feature_deny_demo,
    enable_all_domains        => $modsecurity_feature_deny_demo,
    disable_all_domains       => $modsecurity_feature_deny_demo,
    has_modsecurity_installed => $modsecurity_feature_allow_demo
);

# Globals
my $logger;
my $locale;

# Caches
my $doman_data_cache;    # Keeps a copy of the domain interrelations so we don't have to load it from disk each time.

=head1 NAME

Cpanel::API::ModSecurity

=head1 DESCRIPTION

UAPI functions related to the management of ModSecurity by cPanel users.

=head2 list_domains

=head3 Purpose

List of domains with their mod_security status belonging to this account.

=head3 Arguments

N/A

=head3 Returns

=over

=item An array where each item has the following structure:

=over

=item 'domain': string - name of the domain

=item 'enabled': boolean - 1 if mod_security is enabled, 0 if mod_security is disabled

=item 'dependencies': Other related domains which will be impacted by changes to this
domain's enabled/disabled status.

=item 'searchhint': A comma-separated list of search terms related to this domain,
to aid the development of filtering on the caller's side.

=item 'type': The type of domain. Can be 'main' or 'sub'.

=back

=back

=cut

sub list_domains {
    my ( $args, $result ) = @_;

    # Setups the globals
    _initialize();

    my $domains  = _get_domain_data(1);
    my $enabled  = 0;
    my $disabled = 0;

    my @results;
    foreach my $domain_hr (@$domains) {
        my $status = _enabled_for_domain( $domain_hr->{domain} );
        if ($status) {
            $enabled++;
        }
        else {
            $disabled++;
        }

        push @results,
          {
            %$domain_hr,
            'enabled' => _enabled_for_domain( $domain_hr->{domain} ),
          };
    }

    $result->data( \@results );
    $result->metadata(
        'modsec',
        {
            'total_disabled' => $disabled,
            'total_enabled'  => $enabled,
        }
    );

    return 1;
}

=head2 enable_domains

=head3 Purpose

Enable ModSecurity for the requested list of domains belonging to this account.

=head3 Arguments

=over

=item 'domains': string - Comma-separated list of domains to enable. (They must belong to your account.)

=back

=head3 Returns

=over

=item An array where each item has the following structure.

=over

=item 'domain': string - name of the domain

=item 'enabled': boolean - 1 if mod_security is enabled, 0 if mod_security is disabled

=item 'type': The type of the domain. Can be either 'main' or 'sub'.

=item Other fields returned by this function are currently not useful.

=back

=back

If an error occurred because any of the domains were invalid, they will be litsed in
an array called B<invalid_domains>.

=cut

sub enable_domains {

    my ( $args, $result ) = @_;
    my ($domains) = $args->get('domains');

    # Setups the globals
    _initialize();

    if ( !$domains ) {
        $result->error('Invalid parameter: You did not provide any domains in the call to enable_domains.');
        $result->data( { 'no_domains_provided' => 1 } );
        return;
    }

    my $domains_ar = [ split /,/, $domains ];

    # Check if the domains belong to this user
    my $invalid_domains = _check_domains($domains_ar);
    if ( scalar @$invalid_domains > 0 ) {
        $result->error( 'The following domains do not belong to your account: [_1]', @$invalid_domains );
        $result->data( { 'invalid_domains_provided' => 1, 'invalid_domains' => $invalid_domains } );
        return;
    }

    my $answer = Cpanel::AdminBin::Call::call( 'Cpanel', "modsecurity", "DOMAIN_MODSEC_ENABLE", @$domains_ar );
    if ( !$answer->{status} ) {
        $result->raw_error( _format_problems( 'Could not enable ModSecurity for the domains.', $answer ) );
    }

    my $domain_problems = _domain_problems($answer);

    my @results;
    foreach my $domain (@$domains_ar) {
        my $data = _get_domain_data_by_domain_name($domain);
        push @results,
          {
            %$data,
            'enabled'   => _enabled_for_domain($domain),
            'exception' => $domain_problems->{$domain}
          };
    }

    $result->data( \@results );

    return $answer->{status};
}

=head2 disable_domains

=head3 Purpose

Disable ModSecurity for the requested list of domains belonging to this account.

=head3 Arguments

=over

=item 'domains': string - Comma-separated list of the domains to disable. (They must belong to your account.)

=back

=head3 Returns

=over

=item An array where each item has the following structure.

=over

=item 'domain': string - name of the domain

=item 'enabled': boolean - 1 if mod_security is enabled, 0 if mod_security is disabled

=item 'type': The type of the domain. Can be either 'main' or 'sub'.

=item Other fields returned by this function are currently not useful.

=back

=back

=cut

sub disable_domains {

    my ( $args, $result ) = @_;
    my ($domains) = $args->get('domains');

    # Setups the globals
    _initialize();

    if ( !$domains ) {
        $result->error('Invalid parameter: You did not provide any domains in the call to disable_domains.');
        $result->data( { 'no_domains_provided' => 1 } );
        return;
    }

    my $domains_ar = [ split /,/, $domains ];

    # Check if the domains belong to this user
    my $invalid_domains = _check_domains($domains_ar);
    if ( scalar @$invalid_domains > 0 ) {
        $result->error( 'The following domains do not belong to your account: [_1]', @$invalid_domains );
        $result->data( { 'invalid_domains_provided' => 1, 'invalid_domains' => $invalid_domains } );
        return;
    }

    my $answer = Cpanel::AdminBin::Call::call( 'Cpanel', "modsecurity", "DOMAIN_MODSEC_DISABLE", @$domains_ar );
    if ( !$answer->{status} ) {
        $result->raw_error( _format_problems( 'Could not disable ModSecurity for the domains.', $answer ) );
    }

    my $domain_problems = _domain_problems($answer);

    my @results;
    foreach my $domain (@$domains_ar) {
        my $data = _get_domain_data_by_domain_name($domain);
        push @results,
          {
            %$data,
            'enabled'   => _enabled_for_domain($domain),
            'exception' => $domain_problems->{$domain}
          };
    }

    $result->data( \@results );

    return $answer->{status};
}

=head2 enable_all_domains

=head3 Purpose

Enable ModSecurity for all the domains belonging to this account. Currently only main domain and addon domains.

=head3 Arguments

NA

=head3 Returns

=over

=item An array where each item has the following structure.

=over

=item 'domain': string - name of the domain

=item 'enabled': boolean - 1 if mod_security is enabled, 0 if mod_security is disabled

=item 'type': The type of the domain. Can be either 'main' or 'sub'.

=item Other fields returned by this function are currently not useful.

=back

=back

=cut

sub enable_all_domains {

    my ( $args, $result ) = @_;

    # Setups the globals
    _initialize();

    my $domains = _get_domain_data();

    my $answer = Cpanel::AdminBin::Call::call( 'Cpanel', "modsecurity", "DOMAIN_MODSEC_ENABLE", map { $_->{domain} } @$domains );
    if ( !$answer->{status} ) {
        $result->raw_error( _format_problems( 'Could not enable ModSecurity for the domains.', $answer ) );
    }

    my $domain_problems = _domain_problems($answer);

    my @results;
    foreach my $domain_hr (@$domains) {
        push @results,
          {
            %$domain_hr,
            'enabled'   => _enabled_for_domain( $domain_hr->{domain} ),
            'exception' => $domain_problems->{ $domain_hr->{domain} }
          };
    }

    $result->data( \@results );

    return $answer->{status};
}

=head2 disable_all_domains

=head3 Purpose

Disable ModSecurity for all the domains belonging to this account. Currently only main domain and addon domains.

=head3 Arguments

NA

=head3 Returns

=over

=item An array where each item has the following structure.

=over

=item 'domain': string - name of the domain

=item 'enabled': boolean - 1 if mod_security is enabled, 0 if mod_security is disabled

=item 'type': The type of the domain. Can be either 'main' or 'sub'.

=item Other fields returned by this function are currently not useful.

=back

=back

=cut

sub disable_all_domains {

    my ( $args, $result ) = @_;

    # Setups the globals
    _initialize();

    my $domains = _get_domain_data();

    my $answer = Cpanel::AdminBin::Call::call( 'Cpanel', "modsecurity", "DOMAIN_MODSEC_DISABLE", map { $_->{domain} } @$domains );
    if ( !$answer->{status} ) {
        $result->raw_error( _format_problems( 'Could not disable ModSecurity for the domains.', $answer ) );
    }

    my $domain_problems = _domain_problems($answer);

    my @results;
    foreach my $domain_hr (@$domains) {
        push @results,
          {
            %$domain_hr,
            'enabled'   => _enabled_for_domain( $domain_hr->{domain} ),
            'exception' => $domain_problems->{ $domain_hr->{domain} }
          };
    }

    $result->data( \@results );

    return $answer->{status};
}

=head2 has_modsecurity_installed

=head3 Purpose

Determines if mod_security is installed on the server.

=head3 Arguments

N/A

=head3 Returns

=over

=item A hash containing:

=over

=item 'installed': boolean - 1 if installed, 0 if not installed.

=back

=back

=cut

sub has_modsecurity_installed {

    my ( $args, $result ) = @_;

    # Setups the globals
    _initialize();

    # This does not require root privileges to check
    my $installed = Cpanel::ModSecurity::has_modsecurity_installed();

    $result->data( { 'installed' => $installed } );

    return 1;
}

sub _get_domain_data_by_domain_name {
    my ($domain)    = @_;
    my $domain_data = _get_domain_data();
    my @data        = grep { $_->{'domain'} eq $domain } @$domain_data;
    return $data[0];
}

sub _get_domain_data {
    my ($force) = @_;

    my $domain_data;
    if ( !$doman_data_cache || $force ) {
        $doman_data_cache = $domain_data = Cpanel::Config::userdata::Load::load_userdata_main($Cpanel::user);
    }
    else {
        $domain_data = $doman_data_cache;
    }

    my @vhosts = ();
    my @deps   = sort @{ $domain_data->{'parked_domains'} };
    my $hint   = join( ',', @deps );
    my $data   = {
        'domain'       => $domain_data->{'main_domain'},
        'type'         => 'main',
        'dependencies' => \@deps,
        'searchhint'   => $hint,
    };
    push( @vhosts, $data );

    my %addons = %{ $domain_data->{'addon_domains'} };
    foreach my $subdomain ( @{ $domain_data->{'sub_domains'} } ) {
        my @addons = sort grep { $addons{$_} eq $subdomain } keys %addons;
        $hint = join( ',', @addons );
        $data = {
            'domain'       => $subdomain,
            'type'         => 'sub',
            'dependencies' => \@addons,
            'searchhint'   => $hint,
        };
        push( @vhosts, $data );
    }

    @vhosts = sort { $a->{'domain'} cmp $b->{'domain'} } @vhosts;

    return \@vhosts;
}

sub _check_domains {
    my ($domains) = @_;
    my $valid_domains = _get_domain_data();

    # Check if the domains belong to this user
    my @invalid_domains;
    foreach my $domain (@$domains) {
        if ( !grep { $_->{'domain'} eq $domain } @$valid_domains ) {
            push @invalid_domains, $domain;
        }
    }

    return \@invalid_domains;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _initialize
# Desc:
#   initialize the logger and local system if they are not already initialized.
# Arguments:
#   NA
# Returns:
#   NA
#-------------------------------------------------------------------------------------------------
sub _initialize {
    $logger ||= Cpanel::Logger->new();
    $locale ||= Cpanel::Locale->get_handle();
    return 1;
}

sub _enabled_for_domain {
    my ($domain) = @_;
    return Cpanel::Config::userdata::Cache::get_modsecurity_disabled( $Cpanel::user, $domain ) ? 0 : 1;
}

sub _format_problems {
    my ( $msg, $answer ) = @_;
    return $msg if 'ARRAY' ne ref $answer->{problems};
    $logger->warn( join( "\n", map { $_->{exception} =~ /(.*)/ } @{ $answer->{problems} } ) );
    my $failed_domains = join( ', ', map { $_->{domain}  ? $_->{domain}    : () } @{ $answer->{problems} } );
    my $other_problems = join( '. ', map { !$_->{domain} ? $_->{exception} : () } @{ $answer->{problems} } );
    if ($failed_domains) {
        $msg .= ' ' . lh()->maketext( 'The system could not update the following domains: [_1]', $failed_domains );    # period belongs at end
    }
    if ($other_problems) {
        $msg .= ' ' . lh()->maketext( 'The following additional problems occurred: [_1]', $other_problems );           # period does not belong at end
    }
    return $msg;
}

sub _domain_problems {
    my ($answer) = @_;
    my %domain_problems;
    for my $p ( @{ $answer->{problems} } ) {
        $domain_problems{ $p->{domain} } = $p->{exception};
    }
    return \%domain_problems;
}

1;
