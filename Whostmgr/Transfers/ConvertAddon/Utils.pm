
# cpanel - Whostmgr/Transfers/ConvertAddon/Utils.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Transfers::ConvertAddon::Utils;

use strict;
use warnings;

use Cpanel::PwCache                 ();
use Cpanel::Exception               ();
use Cpanel::LoadModule              ();
use Cpanel::Config::userdata::Cache ();
use Cpanel::Config::userdata::Load  ();

=head1 NAME

Whostmgr::Transfers::ConvertAddon::Utils

=head1 FUNCTIONS

=head2 get_addon_domain_details(domain,extended_options)

Return a variety of information (HASHREF) about a particular addon domain.

Extended options are options suitable for feeding into L<get_domain_data>.

=cut

sub get_addon_domain_details {
    my ( $domain, $extended_options ) = @_;
    die 'need domain' if !$domain;

    my $domain_data = get_domain_data($extended_options);

    #Would be more ideal, arguably, to die() here, but there’s code in
    #place that expects the return-in-failure.
    return undef if !( $domain_data->{$domain} && $domain_data->{$domain}{'domain_type'} eq 'addon' );

    my $addon_domain_data = $domain_data->{$domain};
    Cpanel::LoadModule::load_perl_module('Cpanel::DIp::IsDedicated');
    Cpanel::LoadModule::load_perl_module('Cpanel::NAT');
    $addon_domain_data->{'has_dedicated_ip'} = Cpanel::DIp::IsDedicated::isdedicatedip( $addon_domain_data->{'ip'} );
    $addon_domain_data->{'ip'}               = Cpanel::NAT::get_public_ip( $addon_domain_data->{'ip'} );

    foreach my $entry ( keys %{$domain_data} ) {
        if (   $domain_data->{$entry}->{'domain_type'} eq 'main'
            && $addon_domain_data->{'owner'} eq $domain_data->{$entry}->{'owner'} ) {
            $addon_domain_data->{'owners_main_domain'} //= $entry;
            $addon_domain_data->{'ipv6'} ||= $domain_data->{$entry}->{'ipv6'};
        }
        if ( $entry =~ m/\.\Q$domain\E$/ && $domain_data->{$entry}->{'domain_type'} eq 'sub' ) {
            push @{ $addon_domain_data->{'subdomains'} }, $entry;
        }
    }

    my $udata = Cpanel::Config::userdata::Load::load_userdata( $addon_domain_data->{'owner'}, $addon_domain_data->{'subdomain'} );
    $addon_domain_data->{'is_https_redirecting'} = $udata->{'ssl_redirect'};

    return $addon_domain_data;
}

sub _auto_get_username {
    return $ENV{'REMOTE_USER'} // Cpanel::PwCache::getusername();
}

our $hasroot_cache      = {};
our $domains_data_cache = {};
our $do_domain_caching  = 0;

=head2 get_domain_data($OPTS)

Grab the domains for a user and return them as an arrayref of hashes.

NOTE: if the user is root, *ALL* domains on the server will be returned.

You can set $do_domain_caching if you are running this in a tight loop to reduce overhead from checking whether the user hasroot, and getting the domains.
This is particularly useful when running L<get_addon_domain_details>, as you probably will be getting details for all the addons of a user and repeatedly wasting time getting the same domains.

Be careful when doing caching however; if you mix root and normal user operation mode, you may get incorrect results.

That said, you B<should not> mix modes in such a fashion, as it is a big-time information disclosure vulnerability.

Options HASHREF description:

=over 4

=item B<user> - User to get domains for.  Defaults to grabbing REMOTE_USER.

=item B<hasroot> - If you already know whether the user has root, just set it.  Probably safest to force this to 0 in most operation.  Only set to 1 if you are absolutely sure you have root!

=item B<only_addons> - Only get addon domains; You'd think this would be used in get_addon_domain_details, but you'd be wrong.

=back

=cut

sub get_domain_data {
    my $opts = shift;

    unless ($do_domain_caching) {
        $hasroot_cache      = {};
        $domains_data_cache = {};
    }

    $opts = {} if !( 'HASH' eq ref $opts );

    $opts->{'user'} //= _auto_get_username();

    if ( !defined( $opts->{'hasroot'} ) ) {
        Cpanel::LoadModule::load_perl_module('Whostmgr::ACLS');
        $hasroot_cache->{ $opts->{user} } //= Whostmgr::ACLS::user_has_root( $opts->{'user'} );
        $opts->{'hasroot'} = $hasroot_cache->{ $opts->{user} };
    }

    $opts->{'only_addons'} //= 0;
    return $domains_data_cache->{ $opts->{user} } if $domains_data_cache->{ $opts->{user} };

    my $ud_cache = Cpanel::Config::userdata::Cache::load_cache();
    return {} if !( 'HASH' eq ref $ud_cache && scalar keys %{$ud_cache} );
    $domains_data_cache->{ $opts->{user} } = _filter_user_domains( $ud_cache, $opts );
    return $domains_data_cache->{ $opts->{user} };
}

sub generate_random_password {
    my $length = shift || 16;

    Cpanel::LoadModule::load_perl_module('Cpanel::Rand::Get');
    Cpanel::LoadModule::load_perl_module('Cpanel::PasswdStrength::Check');
    my ( $random_password, $attempts );
    do {
        $attempts++;
        $random_password = Cpanel::Rand::Get::getranddata( $length, [ 0 .. 9, 'A' .. 'Z', 'a' .. 'z', '$', '#', '%', '!' ] );
    } while ( $attempts <= 10 && !Cpanel::PasswdStrength::Check::check_password_strength( 'app' => 'cpanel', 'pw' => $random_password ) );

    return $random_password;
}

sub make_accesshash_for_user {
    my $homedir = gethomedir_or_die();
    system('/usr/local/cpanel/bin/realmkaccesshash') if !-s $homedir . '/.accesshash';
    return 1;
}

sub gethomedir_or_die {
    my $username = shift || Cpanel::PwCache::getusername();
    my $homedir  = Cpanel::PwCache::gethomedir($username);
    die Cpanel::Exception->create( 'The system could not locate the home directory for the [asis,cPanel] user “[_1]”.', [$username] )
      if !length $homedir;

    return $homedir;
}

sub get_email_account_count_for_domain {
    my ( $user, $domain ) = @_;

    Cpanel::LoadModule::load_perl_module('Whostmgr::Email');
    my $pops = Whostmgr::Email::list_pops_for( $user, $domain );
    return scalar @{$pops};
}

sub get_email_forwarder_count_for_domain {
    my ( $user, $domain ) = @_;

    Cpanel::LoadModule::load_perl_module('Whostmgr::Email::Forwarders');
    my $forwarders = Whostmgr::Email::Forwarders::list_forwarders_for_domain( { 'user' => $user, 'domain' => $domain } );

    my $count = 0;
    foreach my $alias ( keys %{$forwarders} ) {
        $count += scalar @{ $forwarders->{$alias} };
    }
    return $count;
}

sub get_domain_forwarder_count_for_domain {
    my $domain = shift;

    Cpanel::LoadModule::load_perl_module('Whostmgr::Email::DomainForwarders');
    my $dforwarders = Whostmgr::Email::DomainForwarders::list_domain_forwarders_for_domain($domain);

    # A domain can only have one domain forwarder set.
    return ( exists $dforwarders->{$domain} ? 1 : 0 );
}

sub get_autoresponder_count_for_domain {
    my ( $user, $domain ) = @_;

    Cpanel::LoadModule::load_perl_module('Whostmgr::Email::Autoresponders');
    my $autoresponders = Whostmgr::Email::Autoresponders::list_auto_responders_for_domain( { 'user' => $user, 'domain' => $domain } );
    return scalar @{$autoresponders};
}

sub _filter_user_domains {
    my ( $userdata_hr, $opts_hr ) = @_;

    # The userdata is a hash with the following structure:
    # {
    #   'domain.tld' => [
    #      'username',
    #      'reseller',
    #      'domain_type',
    #      'subdomain_associated_with_domain',
    #      'docroot',
    #      'vhostip:port',
    #      'vhostip:port (ssl)',
    #      'ipv6',
    #      'misc (unknown)',
    #   ]
    # }

    # This code had to be commented below to prevent perltidy from making it all 1 line.
    # The fact this map is so complicated argues for a variable in the hash which is built up prior to the return.
    # TODO: This should be considered if this code is ever re-factored.

    my $child_acct_lookup_hr  = _get_child_account_lookup();
    my $parent_acct_lookup_hr = _get_parent_account_lookup();

    return {
        map {
            $_ => {
                'owner'       => $userdata_hr->{$_}->[0],
                'reseller'    => $userdata_hr->{$_}->[1],
                'domain_type' => $userdata_hr->{$_}->[2],
                'subdomain'   => $userdata_hr->{$_}->[3],
                'docroot'     => $userdata_hr->{$_}->[4],
                'ip'          => ( $userdata_hr->{$_}->[5] =~ s/\:\d+$//r ),    #
                (
                    $userdata_hr->{$_}->[7]                                      #
                    ? ( 'ipv6' => ( $userdata_hr->{$_}->[7] =~ s/\,.+$//r ) )    #
                    : ()                                                         #
                ),                                                               #
            }    #
          } grep {    #
            ( $opts_hr->{'only_addons'} ? $userdata_hr->{$_}->[2] eq 'addon' : 1 )                                                        &&    #
              ( $opts_hr->{'hasroot'} || $opts_hr->{'user'} eq $userdata_hr->{$_}->[0] || $opts_hr->{'user'} eq $userdata_hr->{$_}->[1] ) &&    #
              !exists $child_acct_lookup_hr->{ $userdata_hr->{$_}->[0] }                                                                  &&    #
              !exists $parent_acct_lookup_hr->{ $userdata_hr->{$_}->[0] }                                                                       #
          } ( keys %{$userdata_hr} )    #
    };
}

sub _get_parent_account_lookup {
    require Cpanel::LinkedNode::List;
    my $user_workers_ar = Cpanel::LinkedNode::List::list_user_worker_nodes();

    my %lookup;
    @lookup{ map { $_->{'user'} } @$user_workers_ar } = ();

    return \%lookup;
}

sub _get_child_account_lookup {
    require Cpanel::LinkedNode::List;
    my $user_workloads_ar = Cpanel::LinkedNode::List::list_user_workloads();

    my %child_acct_lookup;
    @child_acct_lookup{ map { $_->{'user'} } @$user_workloads_ar } = ();

    return \%child_acct_lookup;
}

1;
