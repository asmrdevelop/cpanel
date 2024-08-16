package Cpanel::Market::SSL;

# cpanel - Cpanel/Market/SSL.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module corrals logic for getting SSL products via the cP Marketplace.
#----------------------------------------------------------------------

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Market::SSL

=head1 DESCRIPTION

This module implements logic that calls into Market provider modules to
request SSL certificates. In theory, everything that is not provider-specific
as part of an SSL purchase via the Market should happen through this module
independently of any specific provider.

=cut

use Try::Tiny;

use Cpanel::AdminBin::Call         ();
use Cpanel::ArrayFunc::Uniq        ();
use Cpanel::CommandQueue           ();
use Cpanel::Exception              ();
use Cpanel::Locale                 ();
use Cpanel::Market                 ();
use Cpanel::Market::SSL::DCV::User ();
use Cpanel::Market::SSL::Utils     ();
use Cpanel::OrDie                  ();
use Cpanel::PwCache                ();
use Cpanel::SSL::Create            ();
use Cpanel::SSL::DefaultKey::User  ();
use Cpanel::Security::Authz        ();
use Cpanel::SSL::Create            ();
use Cpanel::SSL::PendingQueue      ();
use Cpanel::SSL::Utils             ();
use Cpanel::SSLStorage::User       ();
use Cpanel::WebVhosts              ();
use Cpanel::WildcardDomain         ();

# These are in addition to the methods required by Cpanel::Market. These are checked in request_ssl_certificates.
our @_REQUIRED_METHODS = qw(
  get_certificate_if_available
  undo_domain_control_validation_preparation
  prepare_system_for_domain_control_validation
);

=head1 FUNCTIONS

=cut

=head2 request_ssl_certificates( %OPTS )

The “big one”: sends off an SSL order and returns information that
a cP API caller can use to track the order. This sets up the system
to respond to HTTP- and/or DNS-based DCV as the client indicates and
sends the order information into the provider’s C<create_shopping_cart()>
function.

This also creates keys and CSRs as needed.

%OPTS is:

=over

=item * C<provider> - string, e.g., C<cPStore>

=item * C<access_token> - string, should be taken from the return
of the provider’s C<validate_login_token()> function.

=item * C<url_after_checkout> - Optional, string. This may NOT contain
a query string. To maintain state after the browser goes to
C<checkout_url>, as part of redirection to C<url_after_checkout> the
SSL provider will append a query string of C<?order_id=ZZZ>,
where C<ZZZ> is the same order ID that this API call returns.

=item * C<certificates> - An array of hash references. Each hash is
passed into the provider’s C<validate_request_for_one_item()> function
and contains:

=item * C<product_id> - string; corresponds to one of the C<product_id>s
from the return of the provider’s C<get_products_list()> function.

=item * C<price> - float; expressed in U.S. dollars.
This is submitted to the store backend as a verification
to help ensure that the user interface showed the correct price.
If the store finds that the price doesn’t match, it should return an
error, which we will return.

=item * C<subject_names> - An array reference. Each item is either:

    [ dNSName => $name ]

… or:

    { type => 'dNSName', name => $name, dcv_method => $method }

… where C<$name> is a name that goes onto a certificate and C<$method>
is either C<http> or C<dcv>. The array reference implies a C<$method>
of C<http> and is a legacy format; all new callers should submit hash
references.

This will be sent to the provider’s C<convert_subject_names_to_dcv_order_item_parameters()>
function, and the result of that function will be included in the order
sent to the store.

=item * C<vhost_names> - Optional; if given, then this will also prepare
the system
to poll for the certificate and install onto those vhosts. C<*> is a
“magical” value that means “any and all vhosts where this certificate
matches at least one domain”.

=item * C<identity_verification> - Optional, hash reference. If given, this
will be validated via the referenced product’s C<x_identity_verification>
and sent (after the C<product_id>) to the backend after transform via C<convert_ssl_identity_verification_to_order_item_parameters()>. The contents of the hash are
provider-specific.

=back

C<create_shopping_cart> internally receives:

=over

=item * C<access_token> - As described above.

=item * C<url_after_checkout> - As described above.

=item * C<items> - Array of hashrefs. Each hash is:

=over

=item * C<product_id> - As described above.

=item * C<csr> - PEM-encoded.

=item * … the return of C<convert_ssl_identity_verification_to_order_item_parameters>,
if anything.

=item * … the return of C<convert_subject_names_to_dcv_order_item_parameters>,
if anything.

=back

=back

C<request_ssl_certificates()>’s return is a single hash reference:

=over

=item * C<order_id> - string, from the provider

=item * C<checkout_url> - A convenience that provides the value of
the provider’s C<get_checkout_url()> function with the C<order_id>.

=item * C<certificates> - An array of hash references. Each hash is:

=over

=item * C<order_item_id> - string, from the provider

=item * C<key_id> - A reference to a key ID from the user’s SSLStorage.
(cf. L<Cpanel::SSLStorage::User>) This key will be needed to install
the issued SSL certificate.

=back

=back

=cut

# NB: While the internals here could certainly be refactored to leave smaller,
# individually testable chunks, the overall interface complexity probably
# “is what it is”. SSL orders are just complicated. :-/

sub request_ssl_certificates {
    my (%opts) = @_;

    Cpanel::Security::Authz::verify_not_root();

    my $eff_user_name = Cpanel::PwCache::getusername();

    my $provider_name = $opts{'provider'} or do {
        die Cpanel::Exception->create_raw('Missing or falsey “provider”!');
    };

    my $provider_ns = Cpanel::Market::get_and_load_module_for_provider($provider_name);

    _verify_that_module_is_complete_for_ssl($provider_ns);

    my $cp_token = $opts{'access_token'} or do {
        die Cpanel::Exception->create_raw('Missing or falsey “access_token”!');
    };

    my ($redirect_url) = $opts{'url_after_checkout'};
    if ( length($redirect_url) && $redirect_url =~ tr<?><> ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” ([_2]) cannot include a query string.', [ 'url_after_checkout', $redirect_url ] );
    }

    if ( !$opts{'certificates'} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'certificates' ] );
    }

    if ( !@{ $opts{'certificates'} } ) {
        die Cpanel::Exception::create( 'Empty', [ name => 'certificates' ] );
    }

    # We cannot send the Market::SSLInstall notification if they do not have an email populated
    _ensure_users_contact_email_is_populated_if_available(
        'provider_ns'  => $provider_ns,
        'access_token' => $cp_token
    );

    #Copy the certs.
    my @cert_descriptions = map {
        { %$_ }
    } @{ $opts{'certificates'} };

    my %domains_to_validate;

    my %non_wildcard_vhost_names;

    my %product_id_cert = map { $_->{'product_id'} => $_ } grep { $_->{'product_group'} eq 'ssl_certificate' } $provider_ns->can('get_products_list')->();

    #To avoid the need to parse the subject_names multiple times.
    #Indexed by the stringification of the hash reference.
    my %cert_csr_domains;
    my %cert_domain_dcv_method;

    for my $i ( 0 .. $#cert_descriptions ) {
        my $item_desc = $cert_descriptions[$i];

        my @missing = grep { !length $item_desc->{$_} } qw( product_id price subject_names );
        if (@missing) {
            die Cpanel::Exception::create( 'InvalidParameter', 'Certificate #[numf,_1] lacks the following [numerate,_2,parameter,parameters] [list_and_quoted,_3].', [ $i, scalar(@missing), \@missing ] );
        }

        my $product_desc = $product_id_cert{ $item_desc->{'product_id'} };

        my $domain_dcv_method_hr = Cpanel::Market::SSL::Utils::validate_subject_names_non_duplication( $item_desc->{'subject_names'}, $product_desc );
        $cert_domain_dcv_method{$item_desc} = $domain_dcv_method_hr;

        if ( $product_desc->{'x_identity_verification'} ) {
            Cpanel::Market::SSL::Utils::validate_identity_verification(
                $product_desc->{'x_identity_verification'},
                $item_desc->{'identity_verification'},
            );
        }

        my $csr_domains_ar = Cpanel::Market::SSL::Utils::get_csr_domains_from_subject_names( $item_desc->{'subject_names'} );

        $cert_csr_domains{$item_desc} = $csr_domains_ar;

        #Accommodate the “*” magic argument.
        $non_wildcard_vhost_names{$item_desc} = [ _parse_vhost_names_list( $item_desc->{'vhost_names'}, $csr_domains_ar ) ] if defined $item_desc->{'vhost_names'};

        if ( defined $item_desc->{'vhost_names'} ) {
            my $req_vhosts_ar = $non_wildcard_vhost_names{$item_desc};

            #Ensure that each vhost is valid and user-owned.

            if ( !@$req_vhosts_ar ) {
                die Cpanel::Exception::create( 'Empty', [ name => 'vhost_names' ] );
            }

            my %vhost_domains;
            for my $vh ( Cpanel::WebVhosts::list_vhosts($eff_user_name) ) {
                $vhost_domains{ $vh->{'vhost_name'} } = [
                    @{ $vh->{'domains'} },
                    ( $vh->{'proxy_subdomains'} ? @{ $vh->{'proxy_subdomains'} } : () ),
                ];
            }

            #Ensure that each domain matches at least one vhost.
            #Ensure that each vhost matches at least one domain.
            #
            #NOTE: This logic accommodates wildcard domains. As of March 2016
            #the cPanel Store doesn’t allow wildcard domains, but that
            #is likely to change soon.

            my %domain_to_vhost;
            my %vhost_to_domain;

          CSR_DOMAIN:
            for my $d (@$csr_domains_ar) {
                for my $rvh (@$req_vhosts_ar) {
                    next if !grep { Cpanel::WildcardDomain::wildcard_domains_match( $_, $d ) } @{ $vhost_domains{$rvh} };

                    $domain_to_vhost{$d}   = $rvh;
                    $vhost_to_domain{$rvh} = $d;
                }
            }

            for my $rvh (@$req_vhosts_ar) {
                if ( !$vhost_to_domain{$rvh} ) {
                    die Cpanel::Exception->create( '[numerate,_1,The given domain,None of the given domains] ([list_and_quoted,_2]) for certificate #[numf,_3] [numerate,_1,does not match,matches] the website “[_4]”.', [ 0 + @$csr_domains_ar, $csr_domains_ar, 1 + $i, $rvh ] );
                }
            }

            for my $d (@$csr_domains_ar) {
                if ( !$domain_to_vhost{$d} ) {
                    die Cpanel::Exception->create( 'The domain “[_1]” does not match [numerate,_2,the given website,any of the given websites] ([list_and_quoted,_3]) for certificate #[numf,_4].', [ $d, scalar(@$req_vhosts_ar), $req_vhosts_ar, 1 + $i ] );
                }
            }
        }
        else {

            #We only need to validate the domain ownership if we didn’t opt
            #for a web vhost install.
            @domains_to_validate{@$csr_domains_ar} = ();
        }

        $provider_ns->can('validate_request_for_one_item')->(%$item_desc);
    }

    my @domains_to_validate_array = keys %domains_to_validate;

    require Cpanel::Domain::Authz;
    Cpanel::Domain::Authz::validate_user_control_of_domains__allow_wildcard(
        $eff_user_name,
        \@domains_to_validate_array,
    );

    _validate_no_www_subject_names( \@domains_to_validate_array );

    #----------------------------------------------------------------------

    my $queue = Cpanel::CommandQueue->new();

    for my $item_desc (@cert_descriptions) {
        my $key_type = Cpanel::SSL::DefaultKey::User::get($eff_user_name);
        my $key_pem  = Cpanel::SSL::Create::key($key_type);

        $item_desc->{'csr'} = _generate_csr_with_key_from_item( $provider_ns, $key_pem, $item_desc );

        my $storage = Cpanel::SSLStorage::User->new();
        my $key_record;

        my $this_item = $item_desc;

        $queue->add(
            sub {
                Cpanel::OrDie::multi_return(
                    sub {
                        $key_record = $storage->add_key(

                            text          => $key_pem,
                            friendly_name => _make_key_friendly_name( $provider_name, $item_desc ),
                        );
                        $this_item->{'key_id'} = $key_record->{'id'};
                    }
                );
            },
            sub {
                Cpanel::OrDie::multi_return(
                    sub {
                        $storage->remove_key( id => $key_record->{'id'} );
                        delete $this_item->{'key_id'};
                    }
                );
            },
        );

        my %provider_args = map { ( $_ => $item_desc->{$_} ) } qw(
          product_id
          csr
        );

        my $domain_dcv_method_hr = $cert_domain_dcv_method{$item_desc};

        $queue->add(
            sub {
                Cpanel::Market::SSL::DCV::User::prepare_for_dcv(
                    provider          => $provider_name,
                    provider_args     => \%provider_args,
                    domain_dcv_method => $domain_dcv_method_hr,
                );
            },
            sub {
                Cpanel::Market::SSL::DCV::User::undo_dcv_preparation(
                    provider          => $provider_name,
                    provider_args     => \%provider_args,
                    domain_dcv_method => $domain_dcv_method_hr,
                );
            },
            "Undo domain control validation preparation: @{$cert_csr_domains{$item_desc}}",
        );
    }

    my $dcv_convert_cr = $provider_ns->can('convert_subject_names_to_dcv_order_item_parameters');

    my @items_for_shopping_cart;
    for my $cdesc (@cert_descriptions) {
        my @id_params;

        # Identity verification, i.e., for OV and EV certificates
        if ( $cdesc->{'identity_verification'} ) {
            my $convert_cr = $provider_ns->can('convert_ssl_identity_verification_to_order_item_parameters');
            @id_params = $convert_cr->( $cdesc->{'product_id'}, %{ $cdesc->{'identity_verification'} } );
        }

        # Gather a list of DCV arguments
        my @dcv_args;
        if ($dcv_convert_cr) {
            my @sorted_subj_names = _get_csr_sorted_subject_names( $cdesc->{'subject_names'}->@* );

            @dcv_args = $dcv_convert_cr->(
                $cdesc->{'product_id'},
                \@sorted_subj_names,
            );
        }

        my %shopping_cart_item = (
            remote_price => $cdesc->{'price'},
            @id_params,
            ( map { $_ => $cdesc->{$_} } qw( product_id  csr ) ),
            @dcv_args,
        );

        push @items_for_shopping_cart, \%shopping_cart_item;

    }

    my ( $order_id, $order_items_ar );
    $queue->add(
        sub {
            my @order = (
                access_token       => $cp_token,
                url_after_checkout => $redirect_url,
                items              => \@items_for_shopping_cart,
            );

            ( $order_id, $order_items_ar ) = $provider_ns->can('create_shopping_cart')->(@order);
        },
    );

    $queue->run();

    #----------------------------------------------------------------------
    try {
        my $poll = Cpanel::SSL::PendingQueue->new();

        for my $i ( 0 .. $#cert_descriptions ) {
            my $item = $cert_descriptions[$i];

            if ( $item->{'vhost_names'} ) {
                $poll->add_item(
                    provider              => $provider_name,
                    product_id            => $item->{'product_id'},
                    order_id              => $order_id,
                    order_item_id         => $order_items_ar->[$i]{'order_item_id'},
                    vhost_names           => $non_wildcard_vhost_names{$item},
                    csr                   => $item->{'csr'},
                    identity_verification => $item->{'identity_verification'},

                    #New for v74
                    domain_dcv_method => $cert_domain_dcv_method{$item},
                );
            }
        }

        $poll->finish();

        Cpanel::AdminBin::Call::call(
            'Cpanel',
            'ssl_call',
            'START_POLLING',
        );
    }
    catch {
        warn "$_";
    };

    #----------------------------------------------------------------------

    return {
        order_id     => $order_id,
        checkout_url => scalar $provider_ns->can('get_checkout_url')->($order_id),
        certificates => [
            map {

                #Nothing else should be needed … ?
                {
                    order_item_id => $order_items_ar->[$_]{'order_item_id'},
                    key_id        => $cert_descriptions[$_]{'key_id'},
                }
            } 0 .. $#cert_descriptions
        ],
    };
}

# The input list is sorted in submission order. We, though, need to sort
# by CSR order. (See convert_subject_names_for_csr().) That’s a bit messier
# than it would ideally be, but at least we can wrap it up nicely here.
#
sub _get_csr_sorted_subject_names (@subj_name_hrs) {
    Cpanel::Market::SSL::Utils::normalize_subject_names( \@subj_name_hrs );

    my %domain_dcv_method = map { @{$_}{ 'name', 'dcv_method' } } @subj_name_hrs;

    my @sorted_subj_names = Cpanel::Market::SSL::Utils::convert_subject_names_for_csr(@subj_name_hrs);

    Cpanel::Market::SSL::Utils::normalize_subject_names( \@sorted_subj_names );

    $_->{'dcv_method'} = $domain_dcv_method{ $_->{'name'} } for @sorted_subj_names;

    return @sorted_subj_names;
}

sub set_url_after_checkout {
    my (%opts) = @_;

    Cpanel::Security::Authz::verify_not_root();

    my $eff_user_name = Cpanel::PwCache::getusername();

    my $provider_name = $opts{'provider'} or do {
        die Cpanel::Exception->create_raw('Missing or falsey “provider”!');
    };

    my $provider_ns = Cpanel::Market::get_and_load_module_for_provider($provider_name);

    my $cp_token = $opts{'access_token'} or do {
        die Cpanel::Exception->create_raw('Missing or falsey “access_token”!');
    };

    my $redirect_url = $opts{'url_after_checkout'} or do {
        die Cpanel::Exception->create_raw('Missing or falsey “url_after_checkout”!');
    };
    if ( $redirect_url =~ tr<?><> ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” ([_2]) cannot include a query string.', [ 'url_after_checkout', $redirect_url ] );
    }

    my $order_id = $opts{'order_id'} or do {
        die Cpanel::Exception->create_raw('Missing or falsey “order_id”!');
    };

    return $provider_ns->can('set_url_after_checkout')->(
        'order_id'           => $order_id,
        'access_token'       => $cp_token,
        'url_after_checkout' => $redirect_url
    );
}

sub _validate_no_www_subject_names {
    my ($domains_ar) = @_;

    my @www_domains = grep { index( $_, 'www.' ) == 0 } @$domains_ar;

    if (@www_domains) {
        my @base_domains = map { substr( $_, 4 ) } @www_domains;

        die Cpanel::Exception::create( 'InvalidParameter', 'This interface automatically adds the “[_1]” subdomain to every requested “[_2]” subject name. Request [list_and_quoted,_3] instead of [list_and_quoted,_4].', [ 'www.', 'dNSName', \@base_domains, \@www_domains ] );
    }

    return;
}

# We need to ensure the the cPanel account knows
# where to send the Market::SSLInstall notification
# in the event they have not yet entered a contact
# email address.
#
# Note: Its possible that the provider does
# not have a way to pass back the email so
# this is not fatal we do not get an email back
# from the provider.
#
sub _ensure_users_contact_email_is_populated_if_available {
    my (%opts) = @_;

    my $provider_ns = $opts{'provider_ns'} or do {
        die Cpanel::Exception->create_raw('Missing or falsey “provider_ns”!');
    };

    my $access_token = $opts{'access_token'} or do {
        die Cpanel::Exception->create_raw('Missing or falsey “access_token”!');
    };

    $provider_ns =~ s<\ACpanel::Market::Provider::><> or do {
        die Cpanel::Exception->create_raw("Bad provider module namespace: $provider_ns");
    };

    Cpanel::AdminBin::Call::call(
        'Cpanel',     'market', 'SYNC_CONTACT_EMAIL_FROM_PROVIDER_IF_NEEDED',
        $provider_ns, $access_token,
    );

    return 1;
}

#Here we implement the “magic” vhost_names value that the
#docs above discuss: substitute all vhosts
#that have at least one domain name that matches the certificate.
#
sub _parse_vhost_names_list {
    my ( $vhost_names_ar, $cert_domains_ar ) = @_;

    my @real_vhost_names;

    for my $vh_name ( Cpanel::ArrayFunc::Uniq::uniq(@$vhost_names_ar) ) {
        if ( $vh_name eq '*' ) {
            my @vhs = Cpanel::WebVhosts::list_vhosts( Cpanel::PwCache::getusername() );

            for my $vh_hr (@vhs) {
                next if !Cpanel::SSL::Utils::validate_domains_lists_have_match(
                    [
                        @{ $vh_hr->{'domains'} },
                        ( $vh_hr->{'proxy_subdomains'} ? @{ $vh_hr->{'proxy_subdomains'} } : () ),
                    ],
                    $cert_domains_ar,
                );
                push @real_vhost_names, $vh_hr->{'vhost_name'};
            }
        }
        else {
            push @real_vhost_names, $vh_name;
        }
    }

    return Cpanel::ArrayFunc::Uniq::uniq(@real_vhost_names);
}

sub _generate_csr_with_key_from_item {
    my ( $provider_ns, $key_pem, $item_desc ) = @_;

    my @subject_names = Cpanel::Market::SSL::Utils::convert_subject_names_for_csr( @{ $item_desc->{'subject_names'} } );

    my @subject_parts;
    if ( $item_desc->{'identity_verification'} ) {
        @subject_parts = $provider_ns->can('convert_ssl_identity_verification_to_csr_subject')->( $item_desc->{'product_id'}, %{ $item_desc->{'identity_verification'} } );
    }

    return Cpanel::SSL::Create::csr(
        subject_names => \@subject_names,
        key           => $key_pem,
        subject       => [
            @subject_parts,
            ( $item_desc->{'subject'} ? @{ $item_desc->{'subject'} } : () ),
            [ commonName => $subject_names[0][1] ],
        ],
    );
}

sub _make_key_friendly_name {
    my ( $provider, $order ) = @_;

    my $locale = Cpanel::Locale->get_handle();

    #The old array subject_names are preserved for old modules that don’t
    #support DNS DCV.
    my @names = map { ref eq 'ARRAY' ? $_->[1] : $_->{'name'} } @{ $order->{'subject_names'} };

    return $locale->maketext( '[list_and,_1] (auto-generated for “[_2]” on [datetime,_3,date_format_short] at [datetime,_3,time_format_short] [asis,UTC])', \@names, $provider, time );
}

sub _verify_that_module_is_complete_for_ssl {
    my ($module) = @_;

    my @missing = grep { !$module->can($_) } @_REQUIRED_METHODS;

    return if !@missing;

    die Cpanel::Exception->create( 'The module “[_1]” is missing the required [numerate,_2,method,methods] [list_and_quoted,_3].', [ $module, scalar(@missing), \@missing ] );
}

1;
