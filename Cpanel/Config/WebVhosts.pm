
# cpanel - Cpanel/Config/WebVhosts.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Config::WebVhosts;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::WebVhosts - Queries against user web vhosts configuration.

=head1 SYNOPSIS

    my $vhsconf = Cpanel::Config::WebVhosts->load( 'billy' );

    my $main_domain = $vhsconf->main_domain();

    my @subdomains = $vhsconf->subdomains();
    my @parked_domains = $vhsconf->parked_domains();
    my %parked_vhost = $vhsconf->addon_domains();

    my @fqdns = $vhsconf->ssl_proxy_subdomains_for_vhost( VHOST_NAME );

    #See below for the structure of the returned hash reference.
    my $proxies_z_hr = $vhsconf->ssl_proxy_subdomains_zone_hash_for_vhost( VHOST_NAME );
    my $proxies_l_hr = $vhsconf->ssl_proxy_subdomains_label_hash_for_vhost( VHOST_NAME );

=head1 DESCRIPTION

This module wraps a cPanel user’s main “userdata” datastore with
useful queries against that data to determine such information as
SSL service (formerly proxy) subdomains.

The name “userdata” is avoided in the module name in the eventual hope of
minimizing the use of this term moving forward; the datastore concerns
the configuration of web virtual hosts specifically, not of users themselves
nor of virtual hosts for other services such as FTP.

=head1 SSL SERVICE (formerly PROXY) SUBDOMAINS

In order to have SSL for service (formerly proxy) subdomains, we create special aliases
on the vhosts for the subdomains along with C<mod_rewrite> rules that
redirect traffic for those domain names as appropriate.

(Likewise, the “catch-net”, non-SSL service (formerly proxy) subdomain vhost also has to
redirect traffic for any domain control validation (DCV) checks that may
come in.)

=head1 “VHOST NAME”

For this module, the term “virtual host name” refers to the “ID” of the
vhost. As of v64 this is expressed as the Apache configuration’s C<ServerName>;
however, the concept is broader than merely this, and many parts of our code
base are built with an eye to allowing vhost names to be arbitrary strings,
independent of the actual domains on the vhost.

=head1 METHODS

=cut

use Cpanel::Config::userdata::Utils    ();
use Cpanel::Context                    ();
use Cpanel::WebVhosts::ProxySubdomains ();

=head2 I<CLASS>->load( USERNAME )

Instantiates this class using the saved data for the given user. Presently
this is the only way to instantiate this class; in the future, a C<new()>
method may facilitate creation of this datastore via this class.

=cut

sub load {
    my ( $class, $username ) = @_;

    require Cpanel::Config::userdata::Load;
    my $ud = Cpanel::Config::userdata::Load::load_userdata_main($username);
    if ( !$ud || !$ud->{'main_domain'} ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("No vhosts config data for user “$username”");
    }

    return $class->_from_userdata_main( $ud, $username );
}

=head2 I<OBJ>->main_domain()

Returns the main domain (string).

=cut

sub main_domain {
    my ($self) = @_;

    return $self->{'_ud'}{'main_domain'};
}

=head2 @fqdns = I<OBJ>->subdomains()

Returns the account’s list of subdomains.
This includes the “subdomain” part of addon domains.

Note that these are only those domains
that are created as “subdomains”; for example, if a user who has
C<example.com> creates C<foo.example.com> but as a parked domain rather
than as a subdomain, then this class considers C<foo.example.com> to be
a parked domain and B<not> a subdomain, even though it’s trivially
a “subdomain” as far as DNS goes.

=cut

sub subdomains {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return @{ $self->{'_ud'}{'sub_domains'} };
}

=head2 @fqdns = I<OBJ>->parked_domains()

Returns the account’s list of parked domains. This does B<NOT> include
the “parked” part of addon domains.

=cut

sub parked_domains {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return @{ $self->{'_ud'}{'parked_domains'} };
}

=head2 %parked_vhost = I<OBJ>->addon_domains()

Returns a list of key/value pairs that describes the user’s addon
domains: each parked domain is a key, and the corresponding
vhost/subdomain name is the value.

For example, if a user with C<example.com> creates an addon
C<greatexamples.com> with subdomain part C<great.example.com>,
then this function will return C<greatexamples.com> and
C<great.example.com>, in that order.

=cut

sub addon_domains {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return %{ $self->{'_ud'}{'addon_domains'} };
}

=head2 $subdomains_to_addons_map_hr = I<OBJ>->subdomains_to_addons_map()

Returns a hashref of key/value pairs that describes the user’s subdomains that
are linked to addon domains: each subdomain is a key, and the corresponding
addon domain (alias) are contains an arrayref as the value.

For example, if a user with C<example.com> creates an addon
C<greatexamples.com> with subdomain part C<great.example.com>,
then this function will return C<great.example.com> as the key
and an array ref with C<greatexamples.com> as the first value.

WARNING: The arrayref of aliases is not ordered and may change between
calls to this function!

=cut

sub subdomains_to_addons_map {
    my ($self) = @_;

    return $self->{'_ud_index'}{'subdomains_to_addons_map'} if $self->{'_ud_index'}{'subdomains_to_addons_map'};

    my $subdomains_to_addons_map_hr = $self->{'_ud_index'}{'subdomains_to_addons_map'} = {};

    foreach my $addon ( keys %{ $self->{'_ud'}{'addon_domains'} } ) {
        push @{ $subdomains_to_addons_map_hr->{ $self->{'_ud'}{'addon_domains'}{$addon} } }, $addon;
    }

    return $self->{'_ud_index'}{'subdomains_to_addons_map'};
}

=head2 I<OBJ>->all_created_domains()

Returns a list of all created domains in the vhost configuration.
(NB: “created”, in this case, meaning exclusive of “www”,
“mail”, and service (formerly proxy) subdomains).

=cut

sub all_created_domains {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    return @{ $self->all_created_domains_ar() };
}

=head2 I<OBJ>->all_created_domains_ar()

The same as all_created_domains except it returns an arrayref.

=cut

sub all_created_domains_ar {
    my ($self) = @_;
    return Cpanel::Config::userdata::Utils::get_all_domains_from_main_userdata_ar( $self->{'_ud'} );
}

=head2 I<OBJ>->ssl_proxy_subdomains_zone_hash_for_vhost( VHOST_NAME )

Gives back a hash reference that describes SSL service (formerly proxy) subdomains
that this virtual host contains. This hash is keyed on the DNS zone.
An example structure:

    {
        'parkeddomain.tld' => [ 'cpanel', 'webmail' ],
        'maindomain.tld' => [ 'cpanel' ],
    }

=cut

sub ssl_proxy_subdomains_zone_hash_for_vhost {
    my ( $self, $vhname ) = @_;

    die 'Need a vhost name!' if !$vhname;

    my $proxy_hr = $self->_determine_proxy_subdomains( 'zone', $vhname );

    return $proxy_hr;
}

=head2 I<OBJ>->ssl_proxy_subdomains_label_hash_for_vhost( VHOST_NAME )

Gives back a hash reference that describes SSL service (formerly proxy) subdomains
that this virtual host contains. This hash is keyed on the leftmost
label of the subdomain. An example structure:

    {
        cpanel => [ 'parkeddomain.tld', 'maindomain.tld' ],
        webmail => [ 'parkeddomain.tld' ],
    }

=cut

sub ssl_proxy_subdomains_label_hash_for_vhost {
    my ( $self, $vhname ) = @_;

    die 'Need a vhost name!' if !$vhname;

    my $proxy_hr = $self->_determine_proxy_subdomains( 'label', $vhname );

    return $proxy_hr;
}

=head2 I<OBJ>->ssl_proxy_subdomains_for_vhost( VHOST_NAME )

Gives back a list of SSL service (formerly proxy) subdomains
that this virtual host contains. Each list item is an FQDN.
This will not include any subdomains that have been manually created
via the domain creation APIs.
Example return:

    (
        'cpanel.parkeddomain.tld',
        'webmail.parkeddomain.tld',
        'cpanel.maindomain.tld',
    )

=cut

sub ssl_proxy_subdomains_for_vhost {
    my ( $self, $vhname ) = @_;

    Cpanel::Context::must_be_list();

    return $self->_determine_proxy_subdomains( 'list', $vhname );
}

=head2 I<OBJ>->get_vhost_name_for_domain( DOMAIN_NAME )

Takes in a domain name and looks up the vhost name. Similar to
the intended use of C<Cpanel::WebServer::Userdata>’s method
C<get_vhost_map()>.

This does not handle SSL service (formerly proxy) subdomains; see
C<get_vhost_name_for_ssl_proxy_subdomain()> for that.

Returns undef if no matching vhost can be found.

=cut

sub get_vhost_name_for_domain {
    my ( $self, $dname ) = @_;

    return Cpanel::Config::userdata::Utils::get_vhost_name_for_domain( $self->{'_ud'}, $dname );
}

=head2 I<OBJ>->get_vhost_name_for_ssl_proxy_subdomain( FQDN )

Looks up the vhost name for a service (formerly proxy) subdomain. Similar to
the intended use of C<Cpanel::WebServer::Userdata>’s method
C<get_vhost_map()>.

Returns undef if C<FQDN> is not a service (formerly proxy) subdomain on any
of the user’s vhosts.

=cut

sub get_vhost_name_for_ssl_proxy_subdomain {
    my ( $self, $dname ) = @_;

    my $dname_dot_count = ( $dname =~ tr{.}{} ) - 1;

    for ( $self->main_domain(), $self->addon_domains() ) {

        # Ensure that $base_domain is an ancestor of $dname.
        next if substr( $dname, -length($_) - 1 ) ne ".$_";

        # Ensure that $base_domain is exactly one level above $dname.
        next if tr<.><> != $dname_dot_count;

        my $vh = $self->get_vhost_name_for_domain($_);

        my @proxies = $self->ssl_proxy_subdomains_for_vhost($vh);
        return $vh if grep { $_ eq $dname } @proxies;
    }

    return undef;
}

=head2 I<CLASS>->_from_userdata_main( MAIN_UD_HASH, USERNAME )

Documenting for use in testing only; please don’t use this in production code.
Anyway, it returns an instance of this class when it receives a hash reference
as given by C<Cpanel::Config::userdata::Load::load_userdata_main()>.

=cut

sub _from_userdata_main {
    my ( $class, $ud_main, $username ) = @_;

    die 'Need ud hash & username!' if !$ud_main || !$username;

    return bless { _ud => $ud_main, _username => $username }, $class;
}

=head1 SEE ALSO

=over 4

=item * L<Cpanel::WebServer::Userdata> - A similar class that brings in more
external dependencies, makes admin calls, and accepts vhost aliases as
pseudonyms of vhost names. It was decided that the queries in this module would go here
rather than into this other module
in order to keep the dependency tree lighter.

=item * L<Cpanel::ApacheConf::DCV> - Logic to allow Apache’s C<mod_rewrite>
to handle domain-control validation correctly.

=back

=cut

#----------------------------------------------------------------------

sub _validate_vhost_name {
    my ( $self, $vhname ) = @_;

    return if $vhname eq $self->{'_ud'}{'main_domain'};

    if ( @{ $self->{'_ud'}{'sub_domains'} } ) {

        return if $vhname eq $self->{'_ud'}{'sub_domains'}->[0];

        # Not the first one?
        if ( !$self->{'_ud_index'}{'sub_domains'} ) {
            %{ $self->{'_ud_index'}{'sub_domains'} } = map { $_ => undef } @{ $self->{'_ud'}{'sub_domains'} };
        }
        return if exists $self->{'_ud_index'}{'sub_domains'}{$vhname};
    }

    die "Unrecognized vhost: “$vhname”";
}

#=head2 I<OBJ>->vhost_dns_zones( VHOST_NAME )
#
#A convenience method that returns a list of the DNS zones
#associated with the given vhost.
#
#=cut

sub _vhost_dns_zones {
    my ( $self, $vhname ) = @_;

    Cpanel::Context::must_be_list();

    $self->_validate_vhost_name($vhname);

    if ( $vhname eq $self->{'_ud'}{'main_domain'} ) {
        return (
            $vhname,
            @{ $self->{'_ud'}{'parked_domains'} },
        );
    }

    return () if !scalar keys %{ $self->{'_ud'}{'addon_domains'} };

    my $subdomains_to_addons_map_hr = $self->subdomains_to_addons_map();

    return $subdomains_to_addons_map_hr->{$vhname} ? @{ $self->subdomains_to_addons_map()->{$vhname} } : ();
}

#=head2 I<OBJ>->vhost_created_domains( VHOST_NAME )
#
#Just like C<created_domains()>, but specific to a single named vhost.
#
#=cut

sub _vhost_created_domains {
    my ( $self, $vhname ) = @_;

    Cpanel::Context::must_be_list();

    $self->_validate_vhost_name($vhname);

    if ( $vhname eq $self->main_domain() ) {
        return ( $vhname, @{ $self->{'_ud'}{'parked_domains'} } );
    }

    my $addons_hr = $self->{'_ud'}{'addon_domains'};

    return (
        $vhname,
        ( grep { $addons_hr->{$_} eq $vhname } keys %$addons_hr ),
    );
}

#=head2 I<OBJ>->ssl_proxy_subdomain_labels()
#
#Gives back a list of subdomain labels that are added to all
#SSL virtual hosts—assuming that a given subdomain doesn’t already exist as
#a regular virtual host alias. This takes into account whether the user
#is a reseller or not. Example return:
#
#    (
#        'cpanel',
#        'webmail',
#        'autodiscover',
#        'whm',
#    )
#
#=cut

sub _ssl_proxy_subdomain_labels {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    $self->{'_ssl_psd_labels'} ||= do {
        my @l = Cpanel::WebVhosts::ProxySubdomains::ssl_proxy_subdomain_labels_for_user( $self->{'_username'} );
        \@l;
    };

    return @{ $self->{'_ssl_psd_labels'} };
}

#With apologies to design … this returns a list if $mode is 'list';
#otherwise it returns a hash reference. It seems to make more sense
#to do things this way than to have everything else iterate through
#to reformat the data however.
sub _determine_proxy_subdomains {
    my ( $self, $mode, $vh_name ) = @_;

    my @proxy_sub_labels = $self->_ssl_proxy_subdomain_labels();

    my $vhs_conf_has_fqdn_hr = $self->_get_vhs_conf_has_fqdn();

    my $main_domain = $self->{'_ud'}{'main_domain'};

    #On the account’s main vhost, we only proxy-ify the servername.
    #On any other vhost, we proxy-ify anything BUT than the servername.
    my @proxy_zones = ( $main_domain eq $vh_name ) ? ($vh_name) : $self->_vhost_dns_zones($vh_name);

    #Skip service (formerly proxy) subdomains that already exist on the vhost
    #via the vhosts conf (userdata).
    if ( $mode eq 'list' ) {

        return map {
            my $dns_zone = $_;
            map { !exists $vhs_conf_has_fqdn_hr->{"$_.$dns_zone"} ? "$_.$dns_zone" : () } @proxy_sub_labels
        } @proxy_zones;

    }
    elsif ( $mode eq 'label' ) {
        my %pxy_hash;
        foreach my $pxy_sd (@proxy_sub_labels) {
            push @{ $pxy_hash{$pxy_sd} }, grep { !exists $vhs_conf_has_fqdn_hr->{"$pxy_sd.$_"} } @proxy_zones;
            delete $pxy_hash{$pxy_sd} if !@{ $pxy_hash{$pxy_sd} };
        }

        return \%pxy_hash;

    }
    elsif ( $mode eq 'zone' ) {
        my %pxy_hash;
        foreach my $dns_zone (@proxy_zones) {
            push @{ $pxy_hash{$dns_zone} }, grep { !exists $vhs_conf_has_fqdn_hr->{"$_.$dns_zone"} } @proxy_sub_labels;
            delete $pxy_hash{$dns_zone} if !@{ $pxy_hash{$dns_zone} };

        }

        return \%pxy_hash;

    }

    die( ( caller 0 )[ 0, 3 ] . " unknown mode: “$mode”" );

}

sub _get_vhs_conf_has_fqdn {
    my ($self) = @_;

    return $self->{'_vhs_conf_has_fqdn_hr'} if $self->{'_vhs_conf_has_fqdn_hr'};

    @{ $self->{'_vhs_conf_has_fqdn_hr'} }{ @{ $self->_created_domains_ar() } } = ();

    return $self->{'_vhs_conf_has_fqdn_hr'};
}

#=head2 I<OBJ>->_created_domains_ar()
#
#A convenience method that returns an arrayref of the user’s “created” domains.
#This excludes the various auto-created subdomains
#(as of v64, C<www> and C<mail>) and SSL service (formerly proxy) subdomains (C<cpanel>, etc.).
#
#=cut

sub _created_domains_ar {
    my ($self) = @_;
    return ( $self->{'_created_domains'} ||= Cpanel::Config::userdata::Utils::get_all_domains_from_main_userdata_ar( $self->{'_ud'} ) );
}

1;
